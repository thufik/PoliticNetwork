import Foundation


public enum RequestType: String {
    case GET
    case POST
    case PUT
    case PATCH
    case DELETE
}

public enum ResultError {
    case undecodable
    case invalidToken
    case internalServerError
    case badRequest
    case invalidInfo(String)
    case unauthorized
    case conflict(String)
    case notFound(String)
    case custom(String)
    case empty
}

public enum ResultOperations<T: Codable> {
    case success(T)
    case error(ResultError)
}

public class ResponseModel<T: Codable>: Codable {
    public var result: T?
    public var isSuccess: Bool
    public var message: String
    
    enum CodingKeys: String, CodingKey {
        case result = "Result"
        case isSuccess = "IsSuccess"
        case message = "Message"
    }
}

public protocol ApiProtocol {
    func request<T: Codable>(url: String,
                             method: RequestType,
                             with parameters: [String: Any]?,
                             token: String,
                             completion: @escaping (ResultOperations<T>) -> Void)
}

public class NetworkManager: ApiProtocol  {

    static let shared = NetworkManager(baseUrl: .init(string: "https://google.com.br")!)
    
    let baseUrl: URL
    
    private init(baseUrl: URL) {
        self.baseUrl = baseUrl
    }
    
    public func request<T>(url: String, method: RequestType, with parameters: [String : Any]?, token: String, completion: @escaping (ResultOperations<T>) -> Void) where T : Decodable, T : Encodable {
        let config: URLSessionConfiguration = URLSessionConfiguration.default
        let session: URLSession = URLSession(configuration: config)

        var urlRequest: URLRequest?
        
        switch method {
        case .GET:
            urlRequest = RequestGet.build(url, with: parameters, or: nil)
        case .POST:
            urlRequest = RequestPost.create(url, with: parameters)
        case .PUT:
            urlRequest = RequestPut.create(url, with: parameters, queryParams: nil)
        case .DELETE: break
        case .PATCH:
            urlRequest = RequestPatch.build(url, with: parameters, or: nil)
        }

        guard let myRequest = urlRequest else {
            completion(.error(.badRequest))
            return
        }

        let task = session.dataTask(with: myRequest, completionHandler: { (result, urlResponse, error) in
            var statusCode: Int = 0
            
            if let response = urlResponse as? HTTPURLResponse {
               statusCode = response.statusCode
            }

            guard let data = result else {
                completion(.error(.custom(NSLocalizedString("Something went wrong, check your connection, and try again", comment: ""))))
                return
            }

            do {
                let formatter = DateFormatter()
                
                formatter.calendar = Calendar(identifier: .iso8601)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "YYYY-MM-DD'T'HH:mm:ss.SSS"
                
                
                let decoder = JSONDecoder()
                
                decoder.dateDecodingStrategy = .formatted(formatter)
                
                let decodableData: ResponseModel<T> = try decoder.decode(ResponseModel<T>.self, from: data)
                
                if decodableData.message == "Token expired" || decodableData.message == "Invalid token" {
                    completion(.error(.invalidToken))
                }
                
                switch (decodableData.isSuccess, statusCode) {
                case (false, 400):
                    completion(.error(.badRequest))
                    return
                case (false, 403):
                    completion(.error(.invalidInfo(decodableData.message)))
                    return
                case (false, 404):
                    completion(.error(.notFound(decodableData.message)))
                    return
                case (false, 409):
                    completion(.error(.conflict(decodableData.message)))
                    return
                case (false, 500):
                    completion(.error(.internalServerError))
                    return
                default: break
                }
                
                if decodableData.isSuccess, let result = decodableData.result {
                    completion(.success(result))
                } else if decodableData.isSuccess{
                    completion(.error(.empty))
                } else {
                    completion(.error(.custom(NSLocalizedString("Something went wrong, check your connection, and try again", comment: ""))))
                }
                
            } catch let ex {
                debugPrint(ex)
                completion(.error(.undecodable))
            }
        })
        task.resume()
    }
    
}

struct RequestGet {
    /// Identifier to use query or route format on the request
    static var isQuery: Bool = true // Get this information from a .plist file

    /// Get function: to generate a request for the endpoint structured as QUERY or ROUTE params
    ///
    /// - Parameters:
    ///   - url: Url address for the API endpoint
    ///          If the type of params is ROUTE the URL must be generated as we can see below:
    ///          ---> http://mydomain.com/api/endpoint/{0}/detail/{1}
    ///          So, the route will be updated according the sequence of params sent
    ///   - queryParams: *Optional - all parameters used on the query string on the API endpoint
    /// - Returns: URLRequest object
    static func build(_ url: String, with queryParams: [String: Any]?, or routeParams: [String]?) -> URLRequest? {
        var fullUrl: String = url
        if let query = queryParams, isQuery {
            fullUrl += buildQueryString(with: query)
        } else {
            fullUrl += "/"
            if let params = routeParams {
                for (index, param) in params.enumerated() {
                    fullUrl = fullUrl.replacingOccurrences(of: "{\(index)}", with: "\(param)/")
                }
            }
        }

        guard let urlRequest: URL = URL(string: fullUrl) else { return nil }
        var request: URLRequest = URLRequest(url: urlRequest)
        
        request.httpMethod = "GET"
        
        return request
    }

    fileprivate static func buildQueryString(with queryParams: [String: Any]) -> String {
        var fullUrl: String = "?"
        queryParams.forEach { (key, value) in
            fullUrl += "\(key)=\(value)&"
        }

        fullUrl = String(fullUrl.prefix(fullUrl.count - 1))
        return fullUrl
    }
}

struct RequestPost {
    /// Post function: makes a post on the API endpoint parsing body params
    ///
    /// - Parameters:
    ///   - url: Url address for the API endpoint
    ///   - bodyParams: *Optional - all parameters used on the body on the API endpoint
    /// - Returns: URLRequest object
    static func create(_ url: String,
                       with bodyParams: [String: Any?]?) -> URLRequest? {

        guard let urlRequest: URL = URL(string: url) else { return nil }
        var request: URLRequest = URLRequest(url: urlRequest)
        request.httpMethod = "POST"

        guard let params = bodyParams else { return nil }

        let onlyValues = params.filter { (_, value) -> Bool in
            return value != nil
        }

        guard let postData = try? JSONSerialization.data(withJSONObject: onlyValues, options: []) else { return nil }

        request.httpBody = postData as Data

        return request
    }
}

struct RequestPut {
    /// Post function: makes a post on the API endpoint parsing body params
    ///
    /// - Parameters:
    ///   - url: Url address for the API endpoint
    ///   - bodyParams: *Optional - all parameters used on the body on the API endpoint
    /// - Returns: URLRequest object
    static func create(_ url: String,
                       with bodyParams: [String: Any?]?, queryParams: [String: Any]?) -> URLRequest? {

        var fullUrl: String = url
        
        if let query = queryParams {
            fullUrl += buildQueryString(with: query)
        }
        
        guard let urlRequest: URL = URL(string: fullUrl) else { return nil }
        var request: URLRequest = URLRequest(url: urlRequest)
        request.httpMethod = "PUT"

        guard let params = bodyParams else { return nil }

        let onlyValues = params.filter { (_, value) -> Bool in
            return value != nil
        }

        guard let postData = try? JSONSerialization.data(withJSONObject: onlyValues, options: []) else { return nil }

        request.httpBody = postData as Data

        return request
    }
    
    fileprivate static func buildQueryString(with queryParams: [String: Any]) -> String {
        var fullUrl: String = "?"
        queryParams.forEach { (key, value) in
            fullUrl += "\(key)=\(value)&"
        }

        fullUrl = String(fullUrl.prefix(fullUrl.count - 1))
        return fullUrl
    }
}

struct RequestPatch {
    /// Identifier to use query or route format on the request
    static var isQuery: Bool = true // Get this information from a .plist file

    /// Get function: to generate a request for the endpoint structured as QUERY or ROUTE params
    ///
    /// - Parameters:
    ///   - url: Url address for the API endpoint
    ///          If the type of params is ROUTE the URL must be generated as we can see below:
    ///          ---> http://mydomain.com/api/endpoint/{0}/detail/{1}
    ///          So, the route will be updated according the sequence of params sent
    ///   - queryParams: *Optional - all parameters used on the query string on the API endpoint
    /// - Returns: URLRequest object
    static func build(_ url: String, with queryParams: [String: Any]?, or routeParams: [String]?) -> URLRequest? {
        var fullUrl: String = url
        if let query = queryParams, isQuery {
            fullUrl += buildQueryString(with: query)
        } else {
            fullUrl += "/"
            if let params = routeParams {
                for (index, param) in params.enumerated() {
                    fullUrl = fullUrl.replacingOccurrences(of: "{\(index)}", with: "\(param)/")
                }
            }
        }

        guard let urlRequest: URL = URL(string: fullUrl) else { return nil }
        var request: URLRequest = URLRequest(url: urlRequest)
        
        request.httpMethod = "PATCH"
        
        return request
    }

    fileprivate static func buildQueryString(with queryParams: [String: Any]) -> String {
        var fullUrl: String = "?"
        queryParams.forEach { (key, value) in
            fullUrl += "\(key)=\(value)&"
        }

        fullUrl = String(fullUrl.prefix(fullUrl.count - 1))
        return fullUrl
    }
}
