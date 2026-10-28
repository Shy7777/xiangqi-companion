# 许可与内容边界

除下表另有说明外，仓库自有源码、测试和原创文字采用 GPL-3.0-only。Copyright (c) 2026 Shy7777 and contributors。许可全文位于根目录 LICENSE；本清单不授予任何第三方尚未授予的权利。

| 组成 | 来源与许可 | 本仓库的范围 |
| --- | --- | --- |
| 应用、规则、学习状态与原创练习 | 本项目，GPL-3.0-only | 源码与合成测试；不提供教材权属保证 |
| awesome-xiangqi 索引夹具 | Luca Ferranti and contributors，CC0-1.0 | `Tests/Fixtures/awesome-xiangqi.md`；保留上游许可全文 |
| xiangqi-pwa-offline 接口与外部数据来源 | dffge552，根许可证 MIT | 保留声明；不在仓库预置整库、识别模型或媒体素材 |
| 四盘历史实战 | 象棋谱公开对局记录 | 必要赛事事实及着序，项目另写导学；不收录原站棋评与图片 |
| Pikafish | 引擎代码 GPLv3，权重另有条款 | 外部用户依赖，不随源码或默认构建分发 |
| 用户棋书与学习记录 | 用户自行提供，权利属于各自权利人 | 仅本机处理，不在本仓库许可证范围内 |
| 字体、图形与声音 | macOS 系统字体/声音及本项目绘制代码 | 不复制第三方字体、录音或棋子图片文件 |

## 上游核验

2026-10-28 核对以下版本的根许可，全文保存在 `Docs/licenses/`：

- [awesome-xiangqi](https://github.com/lucaferranti/awesome-xiangqi/tree/8fff91f76b6569a191d8e7fc61295ae92d3bced2)：CC0-1.0。
- [xiangqi-pwa-offline](https://github.com/dffge552/xiangqi-pwa-offline/tree/3ff21f4502a03f30bb0df55db6f3814ceeb989f5)：MIT。

同步会先读取目标提交的 LICENSE，与审核文本的 SHA-256 比较（忽略首尾空白）；变化时不更新本地资料。此检查只验证根许可文本未变，不证明新增文件或题库全部第三方来源均已获授权。PWA 致谢包含第三方残局来源；同步缓存不作为本项目可再次许可的课程包分发。

CC0 索引只覆盖索引本身，不覆盖链接目标。源码中的书目和文章入口是导航，不表示本项目获得整书改编或复制许可。

## 引擎和权重

[Pikafish 官方 README](https://github.com/official-pikafish/Pikafish#terms-of-use)说明引擎 GPLv3 分发要求。[官方权重协议](https://www.pikafish.com/list.html)对 NNUE 有另外的使用限制。项目主许可不能覆盖这些权重，也不能替使用者接受其条款。

默认构建不复制引擎或权重。若下游自行制作含引擎安装包，应提供适用许可、作者归属、对应版本完整源码及获取方式，并另行核对权重分发条件。本仓库不提供这种捆绑包。

## 历史对局出处

以下代码内仅包含着序、必要赛事信息及项目自写的学习提示；对应源地址同时保存在 `Sources/SystematicCurriculum.swift`：

- [胡荣华—杨官璘，1981 年五羊杯](https://www.xqipu.com/qipu/5b21f642-0697-482d-8a91-d65e52a25bdf)
- [吕钦—许银川，2011 年茅山杯](https://www.xqipu.com/qipu/89473f46-4d12-4fea-8153-bf9e7c00bad5)
- [许银川—吕钦，2010 年亚运会选拔赛](https://www.xqipu.com/qipu/8cf50da2-136c-4262-b1a1-1a633bd31947)
- [杨官璘—胡荣华，1979 年全国个人赛](https://www.xqipu.com/qipu/9907c6bd-4bf4-47f8-bc08-b9bd4bb4668c)

网站本身及其文字、图片、题集编排不因此成为开源。发现来源或权利问题时，请提出具体条目以便核查和调整。
