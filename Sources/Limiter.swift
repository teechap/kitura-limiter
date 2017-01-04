import Foundation
import Kitura
import KituraNet
import SwiftRedis
import SwiftyJSON

typealias By = (_ request: RouterRequest) -> String
typealias NextFunc = () -> Void

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

public class Limiter: RouterMiddleware {
    let by: By
    let onRateLimited: RouterHandler
    let expire: Int
    let total: Int
    let defaultLimitJSON: JSON
    let redis: Redis
    let ignoreErrors: Bool

    // TODO: whitelist, onRedisError, skipHeaders/setHeaders functions

    // 150 req/hour default
    public init(redis: Redis, by: @escaping By = defaultByFunc, total: Int = 5, expire: Int = 1000 * 60, onRateLimited: @escaping RouterHandler = defaultOnRateLimited, ignoreErrors: Bool = false) {
        self.redis = redis
        self.by = by
        self.total = total
        self.expire = expire
        self.onRateLimited = onRateLimited
        self.ignoreErrors = ignoreErrors
        self.defaultLimitJSON = JSON([
            "total": total,
            "remaining": total,
            "reset": now() + self.expire
        ])
    }

    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping NextFunc) throws {
        let key = "ratelimit:\(self.by(request))"

        redis.get(key) { (string: RedisString?, redisError: NSError?) in

            if let _ = redisError {
                if ignoreErrors {
                    return next()
                } else {
                    return try! onRateLimited(request, response, next) // onRedisError
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
                        }
                    } else {
                        if json["remaining"].int! >= 0 {
                            return next()
                        }
                    }

                    return try! onRateLimited(request, response, next)
                }
            }
        }
    }
}
