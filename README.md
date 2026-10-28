# 象棋伴练

一个原生 macOS 象棋学习工具：在棋盘上读谱、独立选着、核验后果、比较变化，并在之后重新练习。适合会下棋、希望系统训练的棋手。

开源版只提供软件、原创练习和必要的公开来源索引。**不附带皮卡鱼可执行文件、NNUE 权重、商业教材、私人 CBL 或学习记录。** 本项目不是 Pikafish 或任何教材作者的官方产品。

## 可以做什么

- 手动摆局、双人走棋、悔棋、完整着序浏览与棋谱导入导出。
- 配置本机 Pikafish 后，查看 Top 1–3 候选箭头、评分与后续变化；评分不等于胜率。
- 导入自己有权使用的 CBL 3 / CBR 2 棋书，按章节阅读原注和完整变招树。
- 从原注节点进入判断、反馈、错误前重走、变招比较与到期复习；没有原注的内容不会被包装为名家精讲。
- 分别记录独立完成、辅助练习和隔日复测，不把阅读或照谱复现算作已经掌握。
- 按用户明确操作同步公开资源索引与局面数据。同步核对同一提交的上游许可证；许可变化时停止更新。
- 图片棋盘识别在本机进行，识别结果需逐格确认，不捕获其他应用窗口。

## 构建和打开

需要 Apple Silicon Mac、macOS 13 或更高版本，以及 Apple Command Line Tools。无需额外包管理器或第三方 Swift 依赖。

```sh
git clone https://github.com/Shy7777/xiangqi-companion.git
cd xiangqi-companion
bash build.sh
open 'build/象棋伴练 开源版.app'
```

构建不下载或打包引擎、模型、棋书。没有引擎时仍可读谱、手动走棋和管理局面；引擎判分需要完成下一节的配置。生成的应用使用本机临时签名，未进行 Apple 开发者公证；不要通过关闭系统安全保护解决来源警告。

## 配置本地引擎

从 [Pikafish 官方项目](https://github.com/official-pikafish/Pikafish)或[官方网站](https://www.pikafish.com/)自行取得适合本机的引擎及配套权重，并核对各自条款。

打开应用的“引擎设置”，选择可执行文件和 NNUE 文件，确认来源后保存并重新打开应用。配置外部程序意味着允许它以当前用户权限运行；仅选择可信来源。软件不会代你下载或接受第三方授权。

开发时也可显式设置：

```sh
export XQ_ENGINE_PATH='/absolute/path/to/pikafish'
export XQ_ENGINE_NETWORK='/absolute/path/to/pikafish.nnue'
'build/象棋伴练 开源版.app/Contents/MacOS/XiangqiCompanion'
```

环境变量只影响继承该环境的进程；从 Finder 打开时请使用应用内配置。Pikafish 引擎代码采用 GPLv3，官方 NNUE 权重另有使用限制，不能把二者都视为本项目许可证覆盖的内容。

## 棋书与内容边界

从“跟书学习”导入你自己的棋书。原文件、原注和变招留在本机，不上传至 GitHub 或任何模型服务。导入能力不授予书籍复制、传播或改编权。

公开版未包含现代教材中未核清授权的 10 个摘例教案，也未发布针对私人《弈林新编》版本的逐点改写教案。通用棋书阅读与原注节点练习仍可使用；这不是《弈林新编》全文开源或全书精讲版。

默认数据目录为 `~/Library/Application Support/XiangqiCompanionOpenSource/`，与个人版隔离。需要测试或迁移时可显式设置 `XQ_COMPANION_STATE_DIR`；不要把该目录、导出的学习记录或个人棋书提交到仓库。

## 验证

```sh
# 默认离线，不需要引擎、权重、私人棋书或网络
bash verify.sh

# 在已经配置可信本地引擎后运行真实引擎检查
XQ_ENGINE_PATH='/absolute/path/to/pikafish' \
XQ_ENGINE_NETWORK='/absolute/path/to/pikafish.nnue' \
bash verify.sh --with-engine

# 检查 Git 中拟发布的文件边界
bash scripts/check-publication.sh
```

默认测试明确标注未执行的真实引擎检查；不能把离线通过当作引擎集成通过。CI 只运行无私有资源的构建与离线验证，不缓存或上传用户教材及模型。

## 许可与贡献

本项目自有代码以 **GPL-3.0-only** 发布，见 [LICENSE](LICENSE)。第三方例外、外部引擎与教材边界见 [许可清单](Docs/LICENSING.md)和 [UPSTREAM-NOTICES](Docs/UPSTREAM-NOTICES.txt)。资源索引的许可不会传递给其链接的书、视频或网站。

欢迎小而可验证的改进。提交前请阅读 [贡献指南](CONTRIBUTING.md)，安全问题请按 [SECURITY.md](SECURITY.md) 报告。项目采用 AI 辅助开发，合并内容仍需代码、来源和测试审查；不保证达到特定棋力或专业教学认证。
