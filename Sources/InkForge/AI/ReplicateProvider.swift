import Foundation
import CoreGraphics

class ReplicateProvider: AIProvider {

    let name = "Replicate"
    let supportedModes: [AIMode] = [.generate, .styleTransfer, .inpaint]

    private var currentTask: URLSessionDataTask?
    private var pollTimer: Timer?
    private var isCancelled = false

    private static let baseURL = "https://api.replicate.com/v1/predictions"
    private static let pollInterval: TimeInterval = 1.5
    private static let maxPollTime: TimeInterval = 120

    func process(_ request: AIRequest,
                 progress: @escaping (Double) -> Void,
                 completion: @escaping (Result<AIResponse, AIError>) -> Void) {

        guard let apiKey = AIProviderManager.shared.apiKey(for: name) else {
            completion(.failure(.noAPIKey))
            return
        }

        isCancelled = false

        let body = buildRequestBody(request: request)
        guard let url = URL(string: Self.baseURL) else {
            completion(.failure(.networkError("Invalid URL")))
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 30

        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(.networkError("Failed to encode request: \(error.localizedDescription)")))
            return
        }

        progress(0.05)

        let task = URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if self.isCancelled { completion(.failure(.cancelled)); return }

            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(.invalidResponse))
                return
            }

            // Check for immediate error
            if let errorDetail = json["detail"] as? String {
                completion(.failure(.providerError(errorDetail)))
                return
            }

            guard let predictionURL = (json["urls"] as? [String: Any])?["get"] as? String else {
                completion(.failure(.invalidResponse))
                return
            }

            progress(0.15)

            // Start polling
            self.pollForResult(url: predictionURL, apiKey: apiKey,
                               startTime: Date(), progress: progress, completion: completion)
        }

        currentTask = task
        task.resume()
    }

    func cancel() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Polling

    private func pollForResult(url: String, apiKey: String, startTime: Date,
                               progress: @escaping (Double) -> Void,
                               completion: @escaping (Result<AIResponse, AIError>) -> Void) {

        if isCancelled { completion(.failure(.cancelled)); return }

        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > Self.maxPollTime {
            completion(.failure(.timeout))
            return
        }

        // Progress from 0.15 to 0.85 over the poll duration
        let pollProgress = min(0.15 + (elapsed / Self.maxPollTime) * 0.7, 0.85)
        progress(pollProgress)

        guard let pollURL = URL(string: url) else {
            completion(.failure(.networkError("Invalid poll URL")))
            return
        }

        var request = URLRequest(url: pollURL)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if self.isCancelled { completion(.failure(.cancelled)); return }

            if let error = error {
                completion(.failure(.networkError(error.localizedDescription)))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                completion(.failure(.invalidResponse))
                return
            }

            switch status {
            case "succeeded":
                progress(0.9)
                self.handleSuccess(json: json, progress: progress, completion: completion)

            case "failed":
                let errorMsg = json["error"] as? String ?? "Unknown error"
                completion(.failure(.providerError(errorMsg)))

            case "canceled":
                completion(.failure(.cancelled))

            default:
                // Still processing — schedule next poll
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.pollInterval) {
                    self.pollForResult(url: url, apiKey: apiKey, startTime: startTime,
                                       progress: progress, completion: completion)
                }
            }
        }

        currentTask = task
        task.resume()
    }

    // MARK: - Result Handling

    private func handleSuccess(json: [String: Any],
                               progress: @escaping (Double) -> Void,
                               completion: @escaping (Result<AIResponse, AIError>) -> Void) {
        // Output can be a string URL or array of string URLs
        let outputURL: String?
        if let output = json["output"] as? String {
            outputURL = output
        } else if let outputs = json["output"] as? [Any], let first = outputs.first as? String {
            outputURL = first
        } else {
            completion(.failure(.invalidResponse))
            return
        }

        guard let urlString = outputURL, let url = URL(string: urlString) else {
            completion(.failure(.invalidResponse))
            return
        }

        // Download the image
        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(.networkError("Failed to download image: \(error.localizedDescription)")))
                return
            }

            guard let data = data, let image = ImageConverter.dataToCGImage(data) else {
                completion(.failure(.invalidResponse))
                return
            }

            progress(1.0)
            completion(.success(AIResponse(resultImage: image, text: nil)))
        }
        task.resume()
    }

    // MARK: - Request Building

    private func buildRequestBody(request: AIRequest) -> [String: Any] {
        var input: [String: Any] = [
            "prompt": request.prompt,
        ]

        switch request.mode {
        case .generate:
            // Flux schnell for generation
            input["num_outputs"] = 1
            input["width"] = min(request.width, 1024)
            input["height"] = min(request.height, 1024)

            return [
                "version": "black-forest-labs/flux-schnell",
                "input": input,
            ]

        case .styleTransfer:
            // Use flux-schnell with image prompt
            if let image = request.inputImage, let base64 = ImageConverter.cgImageToBase64(image) {
                input["image"] = "data:image/png;base64,\(base64)"
            }
            input["num_outputs"] = 1

            return [
                "version": "black-forest-labs/flux-schnell",
                "input": input,
            ]

        case .inpaint:
            // SDXL inpainting
            if let image = request.inputImage, let base64 = ImageConverter.cgImageToBase64(image) {
                input["image"] = "data:image/png;base64,\(base64)"
            }
            if let mask = request.maskImage, let base64 = ImageConverter.cgImageToBase64(mask) {
                input["mask"] = "data:image/png;base64,\(base64)"
            }
            input["num_outputs"] = 1

            return [
                "version": "stability-ai/stable-diffusion-inpainting",
                "input": input,
            ]

        case .describe:
            // Not supported by Replicate provider
            return [:]
        }
    }
}
