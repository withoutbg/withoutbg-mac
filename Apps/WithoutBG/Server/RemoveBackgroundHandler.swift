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
        let contentType = req.headers.contentType
        var editParts: ImageUpload?

        if let ct = contentType, ct.type == "multipart" {
            guard let upload = try? req.content.decode(ImageUpload.self) else {
                throw Abort(.badRequest, reason: "Multipart field 'image' not found.")
            }
            imageData = Data(buffer: upload.image.data)
            editParts = upload
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
        if let parts = editParts, parts.keep_mask != nil || parts.remove_mask != nil || parts.matte != nil {
            // Keep / Remove: masks (white = painted) and the previous matte, all image-sized.
            guard parts.keep_mask != nil || parts.remove_mask != nil else {
                throw Abort(.unprocessableEntity, reason: "A matte needs a keep_mask or remove_mask.")
            }
            guard coordinator.supportsEdit else {
                throw Abort(.unprocessableEntity, reason: "This model has no Keep / Remove graph.")
            }
            func decode(_ file: File?, _ name: String) throws -> CGImage? {
                guard let file else { return nil }
                guard let image = ImageUtilities.cgImage(from: Data(buffer: file.data)) else {
                    throw Abort(.unprocessableEntity, reason: "\(name) is not a valid image.")
                }
                return image
            }
            func marks(_ file: File?, _ name: String) throws -> [Bool]? {
                guard let image = try decode(file, name) else { return nil }
                guard let m = ImageUtilities.maskMarks(image, width: cgImage.width, height: cgImage.height) else {
                    throw Abort(.unprocessableEntity, reason: "\(name) size does not match the image.")
                }
                return m
            }
            let keep = try marks(parts.keep_mask, "keep_mask")
            let remove = try marks(parts.remove_mask, "remove_mask")
            let matte = try decode(parts.matte, "matte")
            if let matte, matte.width != cgImage.width || matte.height != cgImage.height {
                throw Abort(.unprocessableEntity, reason: "matte size does not match the image.")
            }
            do {
                result = try await coordinator.edit(preparedImage: cgImage, keep: keep, remove: remove, matte: matte)
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

        let outputImage = returnMatte ? result.alphaMatte : result.processed
        guard let png = ImageUtilities.pngData(from: outputImage) else {
            throw Abort(.internalServerError, reason: "PNG encoding failed.")
        }

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "image/png")
        headers.add(name: "X-Latency-Ms", value: String(result.latencyMs ?? 0))
        var detail = returnMatte ? "matte" : "cutout"
        if let route = result.route {
            headers.add(name: "X-Route-Category", value: route.category)
            headers.add(name: "X-Route-Pipeline", value: route.pipeline)
            detail += " · \(route.category)"
        }
        headers.add(name: "X-Activity-Detail", value: detail)
        return Response(status: .ok, headers: headers, body: .init(data: png))
    }
}

private struct ImageUpload: Content {
    var image: File
    var keep_mask: File?
    var remove_mask: File?
    var matte: File?
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
             optional Keep / Remove fields (same size as the image):
               keep_mask, remove_mask  white = painted; Remove wins where both mark
               matte                   previous result to edit (else processed first)

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
                "multipart/form-data": {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "image": { "type": "string", "format": "binary" },
                      "keep_mask": { "type": "string", "format": "binary", "description": "Keep mask, image-sized, white = keep" },
                      "remove_mask": { "type": "string", "format": "binary", "description": "Remove mask, image-sized, white = remove" },
                      "matte": { "type": "string", "format": "binary", "description": "Previous result to edit (needs a mask)" }
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
                "content": { "image/png": { "schema": { "type": "string", "format": "binary" } } }
              }
            }
          }
        }
      }
    }
    """
}
