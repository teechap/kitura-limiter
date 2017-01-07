import Foundation
import Kitura
import KituraNet
import SwiftRedis
import SwiftyJSON

typealias By = (_ request: RouterRequest) -> String
typealias NextFunc = () -> Void
typealias WhiteList = (_ request: RouterRequest) -> Bool

private func now() -> Int { // ms since epoch
    return Int(Date().timeIntervalSince1970 * 1000)
}

private func defaultOnRateLimited(request: RouterRequest, response: RouterResponse, next: @escaping NextFunc) throws {
    response.status(HTTPStatusCode.tooManyRequests).send("Rate limit exceeded")
    try response.end()
}

private func defaultByFunc(request: RouterRequest) -> String {
    return request.remoteAddress
}

private func defaultWhitelist(request: RouterRequest) -> Bool {
    return false
}

private func defaultOnRedisError(request: RouterRequest, response: RouterResponse, next: @escaping NextFunc) throws {
    response.status(HTTPStatusCode.internalServerError).send("Internal server error")
    try response.end()
}

public class Limiter: RouterMiddleware {
    let by: By
    let onRateLimited: RouterHandler
    let expire: Int
    let total: Int
    let defaultLimitJSON: JSON
    let redis: Redis
    let ignoreErrors: Bool
    let whitelist: WhiteList
    let onRedisError: RouterHandler
    let skipHeaders: Bool

    // 150 req/hour default
    public init(redis: Redis, by: @escaping By = defaultByFunc, total: Int = 150, expire: Int = 1000 * 60 * 60, onRateLimited: @escaping RouterHandler = defaultOnRateLimited, ignoreErrors: Bool = false, whitelist: @escaping WhiteList = defaultWhitelist, onRedisError: @escaping RouterHandler = defaultOnRedisError, skipHeaders: Bool = false) {
        self.redis = redis
        self.by = by
        self.total = total
        self.expire = expire
        self.onRateLimited = onRateLimited
        self.onRedisError = onRedisError
        self.ignoreErrors = ignoreErrors
        self.whitelist = whitelist
        self.skipHeaders = skipHeaders
        self.defaultLimitJSON = JSON([
            "total": total,
            "remaining": total,
            "reset": now() + expire
        ])
    }

    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping NextFunc) throws {

        if whitelist(request) {
            return next()
        }

        let key = "ratelimit:\(self.by(request))"

        redis.get(key) { (string: RedisString?, redisError: NSError?) in

            if let _ = redisError {
                if ignoreErrors {
                    return next()
                } else {
                    return try! onRedisError(request, response, next)
                }
            } else {
                var json: JSON
                if let string = string?.asData {
                    json = JSON(data: string)
                } else {
                    // the key does not exist in redis, assign default json
                    json = defaultLimitJSON
                }

                let n = now()

                if n > json["reset"].int! {
                    json["reset"] = JSON(n + expire)
                    json["remaining"] = JSON(total)
                }

                json["remaining"] = JSON(max((json["remaining"].int!) - 1, -1))

                redis.set(key, value: json.rawString()!, expiresIn: Double(expire/1000)) { (result: Bool, redisError: NSError?) in

                    if let _ = redisError {
                        if ignoreErrors {
                            return next()
                        } else {
                            return try! onRedisError(request, response, next)
                        }
                    } else {

                        if !skipHeaders {
                            let lim = json["total"].int!
                            let rs = ceil((Double(json["reset"].int!) / 1000))
                            let rem = max(json["remaining"].int!, 0)

                            response.headers.append("X-RateLimit-Limit", value: "\(lim)")
                            response.headers.append("X-RateLimit-Reset", value: "\(rs)")
                            response.headers.append("X-RateLimit-Remaining", value: "\(rem)")
                        }

                        if json["remaining"].int! >= 0 {
                            return next()
                        } else {

                            if !skipHeaders {
                                let after = (json["reset"].int! - now()) / 1000
                                response.headers.append("Retry-After", value: "\(after)")
                            }

                            return try! onRateLimited(request, response, next)
                        }
                    }
                }
            }
        }
    }
}
