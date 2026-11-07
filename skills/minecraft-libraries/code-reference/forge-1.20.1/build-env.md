---
name: "minecraft-java-build-env"
description: "Minecraft Java 构建环境专家。涵盖 JDK(Graal/OpenJDK 17)版本要求、Gradle wrapper、ForgeGradle/NeoGradle 配置、用本地/私库做依赖、Maven 国内镜像加速(阿里云/腾讯)、build.gradle 常见报修、.gradle 缓存定位、jar 重映射与签名、CI/publish。当搭建/修复 MC 的 Java 构建环境、处理 Gradle/Maven 依赖拉取失败、版本不匹配、镜像加速时调用。"
---

# Minecraft Java 构建环境专家

搭建、加速、修复 Minecraft Java（Forge/NeoForge/Fabric）构建环境。

## 1. 工具链版本

- **JDK**：Forge/NeoForge 1.20.x → **Java 17**（LTS）；1.18 及以下可 17；更高版本按 `gradle.properties` 与 `sourceCompatibility` 定。
- `JAVA_HOME` 指向目标 JDK；win 下用 `where java` / `java -version` 核对，避免混用旧版。
- **Gradle**：用项目自带 `gradlew`（wrapper 固定版本）最稳，不要手改 `~/.gradle` 全局版本。

## 2. Gradle wrapper 与复用缓存

- `.\gradlew build` 会先下载 wrapper 对应 Gradle（首次慢）。**复用已有版本**可减少重复下载；wrapper 版本写死在 `gradle/wrapper/gradle-wrapper.properties`。
- 依赖缓存：`~/.gradle/caches/modules-2/files-2.1/<groupId>/<artifactId>/...` 可手动定位并 `jar tf` 核对包前缀。
- 无网/镜像环境：把依赖放入本地 `flatDir` 或本地 maven，并在 `build.gradle` 声明 `compileOnly`/`runtimeOnly`/`fg.deobf`。

## 3. build.gradle 关键块

```groovy
plugins { id 'net.minecraftforge.gradle' version '[6.0,6.2)' }
group = '<group>'
version = '1.0.0'
minecraft {
    mappings channel: 'official', version: '1.20.1'   // mojmap
    // parchment: { mappings channel:'parchment', version:'2023.09.03-1.20.1' }
}
dependencies {
    minecraft 'net.minecraftforge:forge:1.20.1-47.4.10'
    compileOnly 'local:someapi:1.0'          // 带 API 做编译即可
    runtimeOnly fg.deobf('local:someapi:1.0') // fg.deobf 反混淆第三方 jar
}
```

- `fg.deobf(...)` 用于把第三方发布版 jar 反混淆成 mojmap 后再编译引用。
- 依赖写清晰可避免“找不到类/方法”，也便于定位 `mandatory` 软硬。

## 4. Maven 国内镜像加速（重点）

构建拉不到依赖/超时多因访问 mavenCentral 慢。在 `~/.gradle/init.gradle`（或 init 脚本）配置镜像：
```groovy
allprojects {
  repositories {
    maven { url 'https://maven.aliyun.com/repository/public' }
    maven { url 'https://maven.tencentrepo.com/netease' }   // 按需
    mavenCentral()
  }
}
```
- 镜像只加速公共依赖；`mavenLocal` 放本地私库产物。
- 注意镜像顺序：私有插件用 `gradlePluginPortal`，公共库走阿里/中央。

## 5. 构建常见错误

- `Could not resolve ...`：网络/镜像问题，或依赖并未在声明的仓库。
- `--refresh-dependencies` 强制刷新；`--info`/`--stacktrace` 定位。
- `reobfJar` 产出**运行时 SRG jar**（发布用）；`build/libs` 里那个才是给玩家/服务端。
- 构建通过但运行崩溃：多为映射命名空间或缺少运行时库（见 `minecraft-mod-dev` §3/§8）。

## 6. 本地 maven 与签名/发布

- 生成 POM 发布到本地：`publishToMavenLocal`，或手写 POM；无 POM 的 flatDir 依赖用 `compileOnly` 即可。
- 发布前 `gradlew build` 零错误（仅允许过时警告）；玩家端 jar 用 reobf 产物。
- 涉及商用/分享注意依赖版权与「断依赖后静默运行」的软依赖策略（见 `minecraft-mod-dev` §7）。

## 7. 环境诊断清单

- 先查 `gradle.properties` 与 `settings.gradle` 的项目/根节点是否一致（rootProject / include）。
- `JAVA_HOME`、wrapper、镜像、`compileOnly vs runtimeOnly`、`deobf` 各环节按序排查。
- 开发机 Win 下注意终端 GBK 会误显 UTF-8 中文，勿据此误判构建失败文案。