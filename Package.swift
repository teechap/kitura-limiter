import PackageDescription

let package = Package(
    name: "KituraLimiter",
    dependencies: [
        .Package(url: "https://github.com/IBM-Swift/Kitura.git", majorVersion: 1),
        .Package(url: "https://github.com/IBM-Swift/Kitura-redis.git", majorVersion: 1),
        .Package(url: "https://github.com/IBM-Swift/Kitura-net.git", majorVersion: 1)
    ]
)
