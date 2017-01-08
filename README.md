##KituraLimiter
Rate limiting middleware for [Kitura](https://github.com/IBM-Swift/Kitura) applications built on [redis](redis.io)

```swift
import Foundation
import Kitura
import SwiftRedis
import KituraLimiter

let redis = Redis() // remember to make sure a redis instance is running

redis.connect(host: "localhost", port: 6379) { (redisError: NSError?) in
    if let error = redisError {
        print("Could not connect to Redis: \(error)")
    } else {
        print("Redis connected")
        // Create a new router
        let router = Router()

        // By default, Limiter allows 150 requests/hour for each IP address
        router.all(middleware: Limiter(redis: redis))

        // Handle HTTP GET requests to /
        router.get("/") { request, response, next in
            response.send("Hello, World!")
            next()
        }

        // Add an HTTP server and connect it to the router
        Kitura.addHTTPServer(onPort: 8090, with: router)

        // Start the Kitura runloop (this call never returns)
        Kitura.run()
    }
}
```

###API options

- `by`: `(_ request: RouterRequest) -> String` Function which returns a unique key to identify the client in redis (the default fn uses the client's `request.remoteAddress`)
- `total`: `Int` (default `150`) Allowed number of requests before getting rate limited
- `expire`: `Int` (default: `1000*60*60`) Amount of time in `ms` before the rate limit is reset
- `whitelist`: `func(_ request: RouterRequest) -> Bool` Optional param allowing the ability to whitelist client requests. Return `true` to whitelist, `false` to pass through to Limiter.
- `skipHeaders`: `Bool` When `true`, the `response.headers` for rate limiting info (e.g `"Retry-After"`) are not set. Default is `false`
- `onRateLimited`: `RouteHandler` optional custom handler for rate-limited clients (default returns a `429` response and tries to `end()`)
- `ignoreErrors`: `Bool` ignore any errors and pass requests to the next() middleware if something goes wrong
- `onRedisError`: `RouteHandler` optional custom handler for when redis throws an error, (default returns a `500` response and tried to `end()`)

###Examples
```swift
func apiToken(request: RouterRequest) -> String {
    // use api token from middleware, cookies, etc.
    return request.userInfo["apiToken"]
}

func isAdmin(request: RouterRequest) -> Bool {
    return request.userInfo["isAdmin"]
}

func onRedisError(request: RouterRequest, response: RouterResponse, next: @escaping NextFunc) throws {
    response.status(HTTPStatusCode.internalServerError).send("This service is awful!")
    try response.end()
}

func onRateLimited(request: RouterRequest, response: RouterResponse, next: @escaping NextFunc) throws {
    response.status(HTTPStatusCode.tooManyRequests).send("I need you to calm down")
    try response.end()
}

router.all(middleware:
    Limiter(
        redis: redis,
        by: apiToken, // limit by api token instead of default ip address
        total: 2, // 2 req/second
        expire: 1000, // 1000 ms
        whitelist: isAdmin, // admin users shouldn't be limited
        ignoreErrors: true, // is rate limiting really *that* important?
        onRedisError: onRedisError, // this is ignored because ignoreErrors is true
        skipHeaders: true, // I don't care if my clients know when they can make more requests!
        onRateLimited: onRateLimited
    )
)
```
