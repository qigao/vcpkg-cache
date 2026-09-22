# Praktor.Native

Praktor 从 `qigao/praktor@master` 构建，由 `qigao/vcpkg-cache` 发布到
qigao GitHub Packages NuGet feed。

本包为 **Release、启用 TurboScript 的 SDK**，包含：

- `sdk/linux-x64`
- `sdk/macos-arm64`
- `sdk/android-arm64-v8a`（NDK API 26、c++_shared）

依赖 Salts.Native 1.2.0、SaltsUtils.Native 2.0.2、CHttp.Native 1.0.0，以及
TurboScript.Native 3.0.0-ci.5.1。TurboScript 使用嵌入式
解释器/JIT SDK，不附带其 CLI 和原生扩展模块。Windows 尚未纳入本次矩阵。

从 `https://nuget.pkg.github.com/qigao/index.json` 还原 Praktor.Native，
NuGet 会一同还原上述依赖。GitHub Packages 需要具有包读取权限的 token。
NuGet 负责文件还原，CMake 消费端需另行配置：

1. 将各 SDK 对应平台目录加入 `CMAKE_PREFIX_PATH`。
2. 设置 `SALTS_ROOT`、`SALTS_UTILS_ROOT`、`CHTTP_ROOT`、`TURBOSCRIPT_ROOT`。
3. 使用共享 vcpkg 工具链满足第三方依赖，链接公开 target：

```cmake
find_package(Praktor CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE Praktor::Praktor)
```

运行时把 SDK 和第三方共享库目录加入系统动态库搜索路径。
Android 应用另需部署 libc++_shared.so；设备运行、系统服务权限和应用沙箱
约束需在目标应用中验证，不把交叉编译成功当作设备运行验收。

Linux/macOS 执行启用脚本引擎的 CTest，然后从重新解包的 SDK 构建和运行
外部消费端，验证命令工作流、脚本能力位和 `ctx.output("answer", 6 * 7)`。
Android 验证 ELF 架构及外部消费端交叉链接。所有平台产物必须记录相同的
Praktor 源码提交，全部通过后才合并打包，并从最终 NuGet 包独立还原、运行脚本工作流，成功后发布。

版本从产品版本派生为唯一 `-script.<run>.<attempt>` 预发布版本；每个平台
manifest 记录源码提交、依赖版本和构建配置。PR 仅构建验证，master 发布。
手动 dispatch 可在 Praktor master 更新后启动新版本发布。

旧 `0.3.0-ci.2.1` 仅包含 Linux x64 core-only，仍是独立的历史版本。
