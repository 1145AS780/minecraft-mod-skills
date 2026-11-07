# 权威血量：getter 插桩、归因栈、镜像同步、L3 自挂 agent

> minecraft-mod-dev skill reference. Index: [../SKILL.md](../SKILL.md) | Guide: [../README.md](../README.md)
> 上半部（饰品 / 伤害闸门 / ASM 补丁 / 血量改写，§14.23-§14.26）见 [14e-bauble-damage-asm.md](14e-bauble-damage-asm.md)
> 适用前提：**第三方能绕过你的 `hurt()`**（直接写 `entityData` 的 `HEALTH`、或自己的伤害管线）。若不能，先回 14e 用闸门就够。

### 14.49 权威血量：getter 插桩 + 归因栈 + 镜像同步（第三方直接改血量时的终极解）

第三方模组（Iron's 的 `LivingEntity` 扩展、技能模组的自定义伤害、其他 Boss 模组）会**绕过你的伤害管线**
直接写 `entityData` 里的 `HEALTH`。只要它们能直接写，你的「阶段血量 / 非致死 / 护盾 / 伤害上限」全部失效。
本项目的解法：**自己维护一份权威血量，并让 `getHealth()` 永远返回权威值**。

**① 权威值容器：`AtomicReference` + fallback 语义**

```java
final class WinefoxHealthState {
    private final AtomicReference<Float> health = new AtomicReference<>();
    private final AtomicReference<Float> maxHealth = new AtomicReference<>();
    float getHealth(float fallback)    { Float v = health.get();    return v != null ? v : fallback; }
    void  setHealth(float value)       { health.set(value); }
}
```

- **`AtomicReference<Float>` 而不是 `volatile float`**：`null` 表示「还没初始化，用原版值」。
  用 `float` 就必须靠魔法值（-1 / NaN）表达「未初始化」，读的时候到处判特例。
- **`fallback` 由调用方传入**（一般是 `super.getHealth()`）：容器不认识实体，实体才认识。

**② 归因栈：谁在写血量，必须能回答**

```java
private static final ThreadLocal<Deque<WriteContext>> CONTEXT = ThreadLocal.withInitial(ArrayDeque::new);

public static void withCause(Boss boss, Cause cause, Runnable action) {
    Deque<WriteContext> stack = CONTEXT.get();
    stack.push(new WriteContext(boss, cause));
    try { action.run(); }
    finally { stack.pop(); if (stack.isEmpty()) CONTEXT.remove(); }   // ← 必须 remove，否则线程池线程泄漏
}

public static Cause currentCause(Boss boss) {
    for (WriteContext ctx : CONTEXT.get()) if (ctx.boss == boss) return ctx.cause;
    return Cause.EXTERNAL_UNKNOWN;                                     // ← 兜底 = 外部
}
```

- **用 `ThreadLocal<Deque>` 而不是单个字段**：血量写入会嵌套（伤害管线 → 效果回调 → 又一次写入）。
  栈才能拿到「最近一层」的归因；单值会被内层覆盖，外层 finally 还原错。
- **`finally` 里 `CONTEXT.remove()`**：`ThreadLocal` 不 remove 会随线程存活（服务器主线程无所谓，
  但**异步/并行 tick、区块线程**上是真泄漏）。
- **兜底返回 `EXTERNAL_UNKNOWN`**：没有归因就等于「外人写的」，这样默认走「防守」分支而不是「放行」。

**③ 预期写入白名单：自己的写入不能被当成外部干扰**

```java
public static void handleExternalHealthWrite(Boss boss, float requested) {
    if (boss.level().isClientSide) return;                              // ← 客户端一律不处理
    if (boss.maidspell$consumeExpectedHealthWrite()) {                   // 自己刚写的那次
        syncMirrors(boss);                                             // 只做镜像，不改权威值
        return;
    }
    float previous = boss.maidspell$authoritativeHealth();
    withCause(boss, Cause.EXTERNAL_UNKNOWN, () -> write(boss, requested));
    if (boss.maidspell$authoritativeHealth() == previous) syncMirrors(boss);  // 写入被拒 → 回滚镜像
}
```

- **`consumeExpectedHealthWrite()` 是一次性令牌**：自己在伤害管线里写原版血量时会置位，
  原版 setter 回调进来时消费掉。**没有这个令牌，自己的写入会被判成外部写入 → 无限回滚循环**。
- **被拒（权威值没变）时必须 `syncMirrors` 回滚**：外部写入虽然被忽略，但原版 `entityData`
  已经被改了，不写回去就会出现「`getHealth` 返回 A、BossBar 显示 B」。

**④ 写入统一入口：`sanitize` 先做，再夹范围**

```java
public static float sanitize(float value, float max) {
    return Float.isFinite(value) ? Mth.clamp(value, 0.0F, max) : max;   // ← NaN/Inf 一律当满血
}
```

- **`Float.isFinite` 必须判**：`NaN` 参与任何比较都为 false，会让「是否掉血」的判断全部失效；
  `Infinity` 会让 `health - damage` 保持 Infinity，Boss 永远打不死。**NaN 归 `max` 而不是 0**：
  归 0 会「莫名秒死」，归满血最多是「这次伤害无效」。

**⑤ 镜像同步必须包在「数据写入抑制」里**

```java
private static void syncMirrors(Boss boss) {
    BossLifecycleAccess.withDataWrite(boss, () -> {
        boss.getEntityData().set(BOSS_HEALTH, encodeSyncFloat(boss.maidspell$authoritativeHealth()));
        LivingEntityHealthAccessor.maidspell$getHealthAccessor().set(boss, 1.0F);   // ← 占位值
    });
}
```

- **`withDataWrite` 是「我正在写，别当成外部写」的抑制开关**，和 ③ 的令牌是同一件事的两端。
- **原版 `HEALTH` 写 `1.0F` 占位**：真正的血量由 `getHealth()` 插桩返回。
  写真实值会让「原版死亡判定（`health <= 0` → `die()`）」在错误时机触发。
- **自定义同步字段用 `encodeSyncFloat`**：`float` 同步走 `EntityDataAccessor<Float>` 会精度抖动，
  编码成 int 位模式再解码可避免「Boss 血条末位乱跳」。

**⑥ 字节码：拦截 `getHealth()` / `getMaxHealth()` 的返回**

`getHealth()` 有**多个 return 点**（提前返回、`if` 分支），所以**不能只改方法头**，要在每个 `FRETURN` 前插桩：

```java
// opcode 174 == FRETURN
public void visitInsn(int opcode) {
    if (opcode == 174) {
        super.visitInsn(87);                                            // POP     丢掉原返回值
        super.visitVarInsn(25, 0);                                       // ALOAD_0 this
        super.visitMethodInsn(182, TARGET, "maidspell$authoritativeHealth", "()F", false);
    }
    super.visitInsn(opcode);                                            // FRETURN 返回权威值
}
```

`getMaxHealth()` 只有一个入口，改方法头更便宜（`instanceof` 判定 + 早返回）：

```java
public void visitCode() {
    Label original = new Label();
    super.visitVarInsn(25, 0);                                          // ALOAD_0
    super.visitTypeInsn(193, AUTHORITY);                                // INSTANCEOF
    super.visitJumpInsn(153, original);                                 // IFEQ → 不是我的实体就跳走
    super.visitVarInsn(25, 0);
    super.visitTypeInsn(192, AUTHORITY);                                // CHECKCAST
    super.visitMethodInsn(185, AUTHORITY, "maidspell$authoritativeMaxHealth", "()F", true);  // INVOKEINTERFACE
    super.visitInsn(174);                                               // FRETURN
    super.visitLabel(original);
    super.visitFrame(3, 0, null, 0, null);                              // F_SAME，必须手写
}
```

- **`ClassWriter(reader, 1)`**：`1` = `COMPUTE_MAXS`，**不开 `COMPUTE_FRAMES`**。
  开了 `COMPUTE_FRAMES` 会重算整个方法的栈帧图，1.20.1 的复杂方法常算出错误帧导致 `VerifyError`；
  不开就必须自己 `visitFrame`（`3` = `F_SAME`）。
- **`instanceof` 用 `193`、接口方法用 `185` 且最后一位 `itf=true`**：写成 `182`（invokevirtual）
  调用接口方法，运行时 `IncompatibleClassChangeError`。
- **插桩前先 `visitMethod` 里 `found[0] = true`**，插桩后检查 `found[0]`：
  方法名/签名变了（映射升级、模组更新）必须 **`return null` 放弃变换并 `LOGGER.error`**，
  绝不能返回半成品字节码——半成品等于启动即崩。

**⑦ 自挂载 agent：JDK 默认禁止，要绕（风险等级 L3，最后手段）**

> **⚠ 风险分级：本节 ⑦ 是库内唯一的「运行时自挂 agent + `retransform`」操作（L3），不是常规手段。**
> **措辞边界**：字节码层操作库内共两处——另一处是 `HurtHeadTransformationService`（L2.5，见下表），
> 走 ModLauncher 官方 coremod 路径，**风险比本节低一档**，别混为一谈。
>
> | 级别 | 手段 | 时机 | 失败后果 | 允许使用的前提 |
> |---|---|---|---|---|
> | L0 | 官方 API / 事件 / Capability | — | 功能不生效 | 直接可用 |
> | L1 | 对自己注册的类做 Mixin | 类加载期 | 自己崩，可回滚 | 目标是自己拥有的类 |
> | L2 | 对第三方类做 Mixin（`@Pseudo`） | 类加载期 | 对方更新即崩，可能连带别的模组 | 版本锁定 + `require` 失败即禁用 |
> | **L2.5** | **ModLauncher `ITransformationService` + `ITransformer`（Forge 官方 coremod 路径，直接产 ASM 指令）** | **类加载期** | **半成品字节码 = 启动即崩；需 `src-bootstrap` 独立源集** | **目标方法在加载期即可确定，不需要运行期热替换** |
> | **L3** | **运行时自挂 agent + `retransform` 改 `LivingEntity` 字节码** | **运行期** | **全局影响所有实体；与其它 agent 共存时行为不可预测；可能被完整性校验拒绝** | **仅当 L0~L2.5 全部被证明不可行，且必须可降级** |
>
> **库内实测的两处字节码层操作**（同一目标类 `net.minecraft.world.entity.LivingEntity`，改的是不同方法）：
>
> | 机制 | 载体 | 改什么 | 行数 |
> |---|---|---|---|
> | `HurtHeadTransformationService`（L2.5） | `ITransformationService`，`src-bootstrap` 源集 | `hurt` / `m_6469_`（头尾注入） | 514 |
> | `AuthoritativeHealthReturnTransformer` + `ByteBuddyAgentInstaller`（L3） | `java.lang.instrument` 自挂载 + `retransform` | `getHealth` / `m_21223_`、`getMaxHealth` | 153 + installer |
>
> **这是个值得记住的教训**：改 `LivingEntity` 的 `hurt` 完全可以用 L2.5（官方支持、无需绕 JDK 内部），
> 而本节 ⑦ 改 `getHealth` 却走了 L3。**判据不是「能不能用 L2.5」，而是「类是否已加载」**——
> 加载期能确定目标 → 优先 L2.5；只有必须对**已加载**的类热替换时，才轮到 L3。
>
> **编号归属（跨文件消歧）**：上表是库内 L0~L3 分级的**唯一权威定义**。
> 14b §14.12 的三档梯度**直接沿用本表编号**（已改为 L0 / L2 / L3），只省略了 L1（自己类 Mixin）与 L2.5——
> 因为那一节的场景全是「改别人的类」，这两级用不上。
> 全库任何位置看到「L3」，一律指**运行时自挂 agent**；「L2.5」指 **ModLauncher 类加载期 ASM**。
>
> 下面的三个「绕法」（`Unsafe` 改 `ALLOW_ATTACH_SELF`、反射清 `Installer.instrumentation`、临时 `URLClassLoader`）
> 全部**依赖 JDK 内部实现细节**：JDK 大版本升级、模块化收紧、或与性能/调试/反作弊类 agent 同时存在时，**没有任何保证**。

```java
public static synchronized void install() {
    if (installed) return;                                              // ← 幂等
    Instrumentation inst = ByteBuddyAgentInstaller.install();
    if (!inst.isRetransformClassesSupported()
            || !inst.isModifiableClass(TARGET_CLASS)
            || !inst.isModifiableClass(LivingEntity.class)) return;      // ← 三重能力检查
    inst.addTransformer(new AuthoritativeHealthReturnTransformer(), true);   // canRetransform=true
    inst.retransformClasses(TARGET_CLASS);                              // ← 已加载的类要 retransform
    inst.retransformClasses(LivingEntity.class);
    installed = true;
}
```

三个必须绕的坑（都是 `ByteBuddyAgentInstaller` 里真实处理的）：

| 坑 | 现象 | 绕法 |
|---|---|---|
| JDK 9+ 禁止 self-attach | `attach` 抛 `IOException: Can not attach to current VM` | 用 `Unsafe` 反射把 `sun.tools.attach.HotSpotVirtualMachine.ALLOW_ATTACH_SELF` 置 `true` |
| `Installer.instrumentation` 已被占用 | `ByteBuddyAgent.install()` 返回**旧的** `Instrumentation`，`retransform` 无效 | 先反射把该静态字段置 `null`，装完再读回；失败时还原旧值 |
| 只用 `ByteBuddyAgent.install()` 拿不到新的 | 上面的结果 | 回退路径：临时 `URLClassLoader`（parent = platform loader）反射 `ByteBuddyAgent.install()` |

- **`addTransformer(t, true)` 的 `true` 是 `canRetransform`**：漏了这个参数，`retransformClasses` 直接忽略你的 transformer，
  表现是「日志说装了，但血量还是原版的」。
- **装失败必须 `return` 而不是抛**：这是「增强」不是「必需」，抛异常会让整个模组不加载。
  失败后所有权威血量逻辑退化为「只用镜像」，功能降级但能跑。
- **`installed` 必须 `synchronized`**：客户端和服务端同进程（单人游戏）时会并发调 `install()`。

**什么时候必须放弃（按顺序判定，命中任一即放弃 L3）**

| 触发条件 | 为什么放弃 | 替代方案 |
|---|---|---|
| L1/L2 能达到同样效果（`@Pseudo` Mixin 改 `getHealth` 返回值） | L3 的代价是**全局的**，L2 只影响一个类 | 回退到 §14.25 的 Mixin 补丁（14e） |
| 目标环境存在其它 agent（性能分析、调试、反作弊、别的模组 `-javaagent`） | 两套 transformer 的叠加顺序不可控，字节码可能被二次改写 | 仅配置显式开启时装载，并输出日志告知 |
| JDK 21+ / 无 `sun.tools.attach` 的发行版（部分 JRE、GraalVM native） | 绕法本身失效，只会留一堆反射异常 | 降级为「仅镜像」，不尝试 attach |
| 服务端有完整性校验 / 反作弊 | 改字节码会被判定作弊或直接踢出 | 放弃，改用镜像 + 伤害入口收敛 |
| 装完只能靠「日志说成功」判断 | 没有可复现的验证 = 无法保证正确 | 先补 §14.47 的 GameTest 断言（14h），再考虑 L3 |
| 需要客户端也生效 | 单人游戏下同进程竞态，且会改到客户端类 | 只在服务端 install，客户端只读镜像 |

> **定位**：L3 是「**别人能绕过你、你又改不了别人**」时的最后一招。
> 若「镜像（14e §14.26 三层守卫）+ 入口收敛（所有伤害走一个方法）」已能覆盖 90% 场景，就不要上 L3
> ——剩下 10% 的收益，不值「全局不可预测」的代价。

**⑧ 伤害数值的三层收敛：最小伤害 → 比例上限 → 自适应 DPS**

```java
static final float MINIMUM_EFFECTIVE_DAMAGE = 0.1F;                    // 防「0 伤害刷触发」

public static float damageCap(Boss boss) {
    double ratio = boss.maidspell$hitDamageCapRatio();
    return ratio <= 0.0 ? Float.MAX_VALUE : (float) (boss.maidspell$bossMaxHealth() * ratio);
}

private static double adaptivePreCapMultiplier(Boss boss) {             // 按实际 DPS 线性衰减
    double ratio = boss.maidspell$adaptiveAttemptedDps() / target;
    if (ratio <= activation) return 1.0;
    double progress = Mth.clamp((ratio - activation) / (saturation - activation), 0.0, 1.0);
    return Mth.lerp(progress, boss.maidspell$adaptiveStartMultiplier(), boss.maidspell$adaptiveMinMultiplier());
}
```

- **伤害上限按「最大血量比例」而不是绝对值**：换难度/换配置时不用重算常量。
- **自适应衰减用 `attemptedDps`（尝试值）而不是 `actualDps`**：用实际值会形成负反馈自锁
  （伤害被压 → 实际 DPS 低 → 倍率回升 → 又秒杀）。
- **`damageBeforeCap` 里所有中间量都要 `Float.isFinite` 兜底**：一次 NaN 污染，Boss 后续全部判定失效。

**一句话判据**：第三方能不能绕过你的伤害钩子？能 → 就必须在 **getter** 上做权威，而不是在 `hurt()` 上加判断。