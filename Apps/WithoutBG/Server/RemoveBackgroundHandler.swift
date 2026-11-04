import CoreGraphics
import Foundation
import Vapor
import WithoutBGCore

/// Records each request in the activity ring buffer.
private struct ActivityMiddleware: AsyncMiddleware {
    let activity: RecentActivity
    let logRequests: () -> Bool

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let start = DispatchTime.now()
        let method = req.method.rawValue
        let path = req.url.path

        do {
            let response = try await next.respond(to: req)
            if logRequests() {
                let latencyMs = responseLatencyMs(from: response, since: start)
                let detail = response.headers.first(name: "X-Activity-Detail")
                await MainActor.run {
                    activity.record(ActivityEntry(
                        method: method,
                        path: path,
                        statusCode: Int(response.status.code),
                        latencyMs: latencyMs,
                        detail: detail
                    ))
                }
            }
            return response
        } catch {
            let statusCode: Int
            let detail: String?
            if let abort = error as? (any AbortError) {
                statusCode = Int(abort.status.code)
                detail = abort.reason
            } else {
                statusCode = 500
                detail = error.localizedDescription
            }
            if logRequests() {
                await MainActor.run {
                    activity.record(ActivityEntry(
                        method: method,
                        path: path,
                        statusCode: statusCode,
                        latencyMs: elapsedMs(since: start),
                        detail: detail
                    ))
                }
            }
            throw error
        }
    }

    private func responseLatencyMs(from response: Response, since start: DispatchTime) -> Int {
        if let header = response.headers.first(name: "X-Latency-Ms"), let ms = Int(header) {
            return ms
        }
        return elapsedMs(since: start)
    }
}

private func elapsedMs(since start: DispatchTime) -> Int {
    Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
}

/// Registers all HTTP routes on the Vapor app.
func registerRoutes(
    on app: Application,
    coordinator: SharedInferenceCoordinator,
    status: ServerStatus,
    activity: RecentActivity
) {
    app.middleware.use(ActivityMiddleware(activity: activity) {
        UserDefaults.standard.localAPILogRequests
    })

    app.get { req throws -> Response in
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/plain; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: helpText(port: status.port)))
    }

    app.get("health") { req throws -> Response in
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        let body = #"{"status":"ok","model":"\#(CoreMLProcessor.modelName)","version":"\#(CoreMLProcessor.modelVersion)"}"#
        return Response(status: .ok, headers: headers, body: .init(string: body))
    }

    app.get("openapi.json") { req throws -> Response in
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/json")
        return Response(status: .ok, headers: headers, body: .init(string: openAPISpec(port: status.port)))
    }

    app.post("v1", "remove-background") { req async throws -> Response in
        let outputParam = req.query[String.self, at: "output"] ?? "cutout"
        let returnMatte = outputParam.lowercased() == "matte"

        let imageData: Data
        var edit = EditFields()
        let contentType = req.headers.contentType
        let isJSON = contentType == .json

        if isJSON {
            guard let body = try? req.content.decode(JSONRequest.self) else {
                throw Abort(.badRequest, reason: "JSON body needs an 'image' field (data URL or base64).")
            }
            guard let data = decodePayload(body.image) else {
                throw Abort(.badRequest, reason: "Field 'image' is not valid base64.")
            }
            imageData = data
            func field(_ value: String?, _ name: String) throws -> Data? {
                guard let value else { return nil }
                guard let data = decodePayload(value) else {
                    throw Abort(.unprocessableEntity, reason: "\(name) is not valid base64.")
                }
                return data
            }
            edit = EditFields(keep: try field(body.keep_mask, "keep_mask"),
                              remove: try field(body.remove_mask, "remove_mask"),
                              matte: try field(body.matte, "matte"),
                              context: body.edit_context)
        } else if let ct = contentType, ct.type == "multipart" {
            guard let upload = try? req.content.decode(ImageUpload.self) else {
                throw Abort(.badRequest, reason: "Multipart field 'image' not found.")
            }
            imageData = Data(buffer: upload.image.data)
            edit = EditFields(keep: upload.keep_mask.map { Data(buffer: $0.data) },
                              remove: upload.remove_mask.map { Data(buffer: $0.data) },
                              matte: upload.matte.map { Data(buffer: $0.data) },
                              context: upload.edit_context)
        } else {
            guard let bytes = req.body.data else {
                throw Abort(.badRequest, reason: "Empty request body.")
            }
            imageData = Data(buffer: bytes)
        }

        guard !imageData.isEmpty else {
            throw Abort(.badRequest, reason: "Empty image data.")
        }

        guard let cgImage = ImageUtilities.cgImage(from: imageData) else {
            throw Abort(.badRequest, reason: "Could not decode image. Supported formats: JPEG, PNG, WebP, HEIC.")
        }

        let result: ProcessorResult
        var reusedContext = false
        if edit.keep != nil || edit.remove != nil || edit.matte != nil {
            // Smart brush: masks (white = painted) and the previous matte, all image-sized.
            guard edit.keep != nil || edit.remove != nil else {
                throw Abort(.unprocessableEntity, reason: "A matte needs a keep_mask or remove_mask.")
            }
            guard coordinator.supportsEdit else {
                throw Abort(.unprocessableEntity, reason: "This model has no Smart brush graph.")
            }
            func decode(_ data: Data?, _ name: String) throws -> CGImage? {
                guard let data else { return nil }
                guard let image = ImageUtilities.cgImage(from: data) else {
                    throw Abort(.unprocessableEntity, reason: "\(name) is not a valid image.")
                }
                return image
            }
            func marks(_ data: Data?, _ name: String) throws -> [Bool]? {
                guard let image = try decode(data, name) else { return nil }
                guard let m = ImageUtilities.maskMarks(image, width: cgImage.width, height: cgImage.height) else {
                    throw Abort(.unprocessableEntity, reason: "\(name) size does not match the image.")
                }
                return m
            }
            let keep = try marks(edit.keep, "keep_mask")
            let remove = try marks(edit.remove, "remove_mask")
            let matte = try decode(edit.matte, "matte")
            if let matte, matte.width != cgImage.width || matte.height != cgImage.height {
                throw Abort(.unprocessableEntity, reason: "matte size does not match the image.")
            }
            // A missing, malformed or stale context is recomputed, never an error.
            let context = edit.context.flatMap { CoreMLProcessor.editContext(token: $0) }
            do {
                result = try await coordinator.edit(preparedImage: cgImage, keep: keep, remove: remove,
                                                    matte: matte, context: context)
                reusedContext = context != nil && result.editContext == context
            } catch let processorError as ProcessorError {
                throw Abort(.internalServerError, reason: processorError.localizedDescription)
            }
        } else {
            do {
                result = try await coordinator.process(preparedImage: cgImage)
            } catch let processorError as ProcessorError {
                throw Abort(.internalServerError, reason: processorError.localizedDescription)
            }
        }

        await MainActor.run { status.requestCount += 1 }

        var headers = HTTPHeaders()
        headers.add(name: "X-Latency-Ms", value: String(result.latencyMs ?? 0))
        var detail = isJSON ? "json" : (returnMatte ? "matte" : "cutout")
        if let route = result.route {
            headers.add(name: "X-Route-Category", value: route.category)
            headers.add(name: "X-Route-Pipeline", value: route.pipeline)
            detail += " · \(route.category)"
        }
        if reusedContext { detail += " · edit only" }
        headers.add(name: "X-Activity-Detail", value: detail)

        if isJSON {
            guard let processed = ImageUtilities.pngData(from: result.processed),
                  let matte = ImageUtilities.pngData(from: result.alphaMatte) else {
                throw Abort(.internalServerError, reason: "PNG encoding failed.")
            }
            let body = JSONResponse(
                processed: "data:image/png;base64," + processed.base64EncodedString(),
                alphaMatte: "data:image/png;base64," + matte.base64EncodedString(),
                latencyMs: result.latencyMs ?? 0,
                routeCategory: result.route?.category,
                routePipeline: result.route?.pipeline,
                // A reused context is echoed as sent; a new one is encoded once.
                editContext: reusedContext ? edit.context : result.editContext?.token
            )
            headers.add(name: .contentType, value: "application/json")
            return Response(status: .ok, headers: headers, body: .init(data: try JSONEncoder().encode(body)))
        }

        let outputImage = returnMatte ? result.alphaMatte : result.processed
        guard let png = ImageUtilities.pngData(from: outputImage) else {
            throw Abort(.internalServerError, reason: "PNG encoding failed.")
        }
        headers.add(name: .contentType, value: "image/png")
        return Response(status: .ok, headers: headers, body: .init(data: png))
    }
}

/// Smart brush fields, whichever body format they came in.
private struct EditFields {
    var keep: Data?
    var remove: Data?
    var matte: Data?
    var context: String?
}

private struct ImageUpload: Content {
    var image: File
    var keep_mask: File?
    var remove_mask: File?
    var matte: File?
    var edit_context: String?
}

/// JSON body, same fields as the Docker server (images as data URLs or base64).
private struct JSONRequest: Content {
    var image: String
    var keep_mask: String?
    var remove_mask: String?
    var matte: String?
    var edit_context: String?
}

private struct JSONResponse: Codable {
    var processed: String
    var alphaMatte: String
    var latencyMs: Int
    var routeCategory: String?
    var routePipeline: String?
    var editContext: String?
}

/// Data URL (`data:<mime>;base64,<data>`) or plain base64 → bytes.
private func decodePayload(_ value: String) -> Data? {
    var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("data:"), let comma = s.firstIndex(of: ",") {
        s = String(s[s.index(after: comma)...])
    }
    return Data(base64Encoded: s, options: .ignoreUnknownCharacters)
}

private func helpText(port: Int) -> String {
    """
    withoutBG Local API
    ===================

    Local background removal powered by on-device Core ML.
    All processing happens on this Mac — nothing leaves the machine.

    Endpoints
    ---------
    GET  /health
         Returns JSON: {"status":"ok","model":"\(CoreMLProcessor.modelName)","version":"\(CoreMLProcessor.modelVersion)"}

    GET  /openapi.json
         OpenAPI 3 specification for this server.

    POST /v1/remove-background
         Remove the background from an image.

         Options
           ?output=cutout   (default) transparent-background PNG cutout
           ?output=matte    grayscale alpha matte PNG

         Accepted content types
           image/jpeg, image/png, image/webp, image/heic — raw body
           multipart/form-data — field name: image
             optional Smart brush fields (same size as the image):
               keep_mask, remove_mask  white = painted; Remove wins where both mark
               matte                   previous result to edit (else processed first)
               edit_context            editContext from the previous edit (JSON)
           application/json — {"image": "<data URL or base64>", ...same fields}
             Response: {"processed", "alphaMatte" (data URLs), "latencyMs",
                        "routeCategory", "routePipeline", "editContext"}
             Smart brush edits return editContext. Send it back as edit_context
             with the next edit of the same image (plus matte and a mask): only
             the Smart brush graph runs. A stale value is recomputed, not an error.

         Response: 200 image/png
           X-Latency-Ms: <ms>
           X-Route-Category: router category, e.g. fine_strand or vehicle
           X-Route-Pipeline: branch that produced the alpha: matting or birefnet
         Errors:   400 / 500  application/json {"error":"<message>"}

    Examples (curl)
    ---------------
    curl http://127.0.0.1:\(port)/health
    curl http://127.0.0.1:\(port)/openapi.json
    curl -X POST --data-binary @photo.jpg -H "Content-Type: image/jpeg" \\
      http://127.0.0.1:\(port)/v1/remove-background -o result.png
    curl -F image=@photo.jpg -F remove_mask=@remove.png -F matte=@result.png \\
      http://127.0.0.1:\(port)/v1/remove-background -o fixed.png
    """
}

private func openAPISpec(port: Int) -> String {
    """
    {
      "openapi": "3.0.3",
      "info": {
        "title": "withoutBG Local API",
        "version": "\(CoreMLProcessor.modelVersion)",
        "description": "Local background removal on your Mac using withoutBG Open Weights."
      },
      "servers": [{ "url": "http://127.0.0.1:\(port)" }],
      "paths": {
        "/health": {
          "get": {
            "summary": "Health check",
            "responses": {
              "200": {
                "description": "Server is running",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "status": { "type": "string" },
                        "model": { "type": "string" },
                        "version": { "type": "string" }
                      }
                    }
                  }
                }
              }
            }
          }
        },
        "/v1/remove-background": {
          "post": {
            "summary": "Remove background from an image",
            "parameters": [
              {
                "name": "output",
                "in": "query",
                "schema": { "type": "string", "enum": ["cutout", "matte"], "default": "cutout" }
              }
            ],
            "requestBody": {
              "required": true,
              "content": {
                "image/jpeg": { "schema": { "type": "string", "format": "binary" } },
                "image/png": { "schema": { "type": "string", "format": "binary" } },
                "application/json": {
                  "schema": {
                    "type": "object",
                    "required": ["image"],
                    "properties": {
                      "image": { "type": "string", "description": "Data URL or base64" },
                      "keep_mask": { "type": "string", "description": "Keep mask, image-sized, white = keep (data URL or base64)" },
                      "remove_mask": { "type": "string", "description": "Remove mask, image-sized, white = remove" },
                      "matte": { "type": "string", "description": "Previous result to edit (needs a mask)" },
                      "edit_context": { "type": "string", "description": "editContext from the previous edit of this image; only the Smart brush graph runs. Stale values are recomputed." }
                    }
                  }
                },
                "multipart/form-data": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "image": { "type": "string", "format": "binary" },
                      "keep_mask": { "type": "string", "format": "binary", "description": "Keep mask, image-sized, white = keep" },
                      "remove_mask": { "type": "string", "format": "binary", "description": "Remove mask, image-sized, white = remove" },
                      "matte": { "type": "string", "format": "binary", "description": "Previous result to edit (needs a mask)" },
                      "edit_context": { "type": "string", "description": "editContext from the previous edit of this image" }
                    }
                  }
                }
              }
            },
            "responses": {
              "200": {
                "description": "PNG cutout or matte",
                "headers": {
                  "X-Latency-Ms": {
                    "description": "Inference latency in milliseconds",
                    "schema": { "type": "integer" }
                  },
                  "X-Route-Category": {
                    "description": "Router category, e.g. fine_strand or vehicle",
                    "schema": { "type": "string" }
                  },
                  "X-Route-Pipeline": {
                    "description": "Branch that produced the alpha: matting or birefnet",
                    "schema": { "type": "string" }
                  }
                },
                "content": {
                  "image/png": { "schema": { "type": "string", "format": "binary" } },
                  "application/json": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "processed": { "type": "string", "description": "Transparent PNG cutout as data URL" },
                        "alphaMatte": { "type": "string", "description": "Grayscale matte as data URL" },
                        "latencyMs": { "type": "integer" },
                        "routeCategory": { "type": "string" },
                        "routePipeline": { "type": "string" },
                        "editContext": { "type": "string", "description": "Smart brush edits only: send back as edit_context with the next edit" }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
}
