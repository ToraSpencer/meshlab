# ![MeshLab Logo](src/meshlab/images/eye64.png) MeshLab（个人 Fork）

[![BuildMeshLab](https://github.com/cnr-isti-vclab/meshlab/actions/workflows/BuildMeshLab.yml/badge.svg)](https://github.com/cnr-isti-vclab/meshlab/actions/workflows/BuildMeshLab.yml)

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.5114037.svg)](https://doi.org/10.5281/zenodo.5114037)

本仓库是 [MeshLab](https://www.meshlab.net) 的个人 Fork（`ToraSpencer/meshlab`），基于官方仓库 [cnr-isti-vclab/meshlab](https://github.com/cnr-isti-vclab/meshlab)，用于学习其源码并进行个人定制。

- 个人开发分支：`develop_tora`
- 同步分支：`main`（仅跟随官方 `main`，不提交定制代码）
- 官方原始 README 保留在 [README_ori.md](README_ori.md)

## 本文目录

- [1. 项目简介](#1-项目简介)
- [2. 发布版本](#2-发布版本)
- [3. 构建与编译（Windows）](#3-构建与编译windows)
  - [3.1. 环境要求](#31-环境要求)
  - [3.2. 安装 Qt](#32-安装-qt)
  - [3.3. 生成 VS 工程](#33-生成-vs-工程)
  - [3.4. 编译与运行](#34-编译与运行)
  - [3.5. 常见问题](#35-常见问题)
- [4. 分支与 Pull Request](#4-分支与-pull-request)
- [5. 从上游同步到开发分支](#5-从上游同步到开发分支)
  - [5.1. 更新 main](#51-更新-main)
  - [5.2. 合并上游更新到 develop_tora](#52-合并上游更新到-develop_tora)
  - [5.3. 处理合并冲突](#53-处理合并冲突)
- [6. 仓库结构](#6-仓库结构)
- [7. 许可证](#7-许可证)
- [8. 版权](#8-版权)
- [9. 引用](#9-引用)
- [10. 联系方式与反馈](#10-联系方式与反馈)

## 1. 项目简介

MeshLab 是一个开源的 3D 三角网格处理与编辑系统，主要用于清理、修复、检查和转换三维扫描得到的大型非结构化网格。它基于 C++ 网格处理库 [VCGlib](http://www.vcglib.net)，支持 Windows、macOS 和 Linux。

## 2. 发布版本

最新版本见 [Releases](https://github.com/cnr-isti-vclab/meshlab/releases)；每夜构建（nightly）见 [GitHub Actions](https://github.com/cnr-isti-vclab/meshlab/actions)。

## 3. 构建与编译（Windows）

仅支持 Windows x64。构建只提供一种方式：先用脚本生成 Visual Studio 工程，再在 VS 中编译。

### 3.1. 环境要求

- Windows 10/11（64 位）
- Visual Studio 2022，安装「使用 C++ 的桌面开发」工作负载（自带 CMake）
- Qt 5.15 MSVC 2019 64-bit（安装方式见 3.2 节）
- Git

首次克隆需连同子模块一起拉取：

```powershell
git clone --recursive git@github.com:ToraSpencer/meshlab.git
cd meshlab
```

### 3.2. 安装 Qt

MeshLab 只支持 Qt 5，推荐用 pip 安装的 `aqtinstall` 下载 Qt 5.15.2：

```powershell
pip install --upgrade aqtinstall
aqt install-qt windows desktop 5.15.2 win64_msvc2019_64 -O "$env:USERPROFILE\Qt"
```

安装结果为 `%USERPROFILE%\Qt\5.15.2\msvc2019_64`。Qt 官方只提供 MSVC 2019 的库，但 MSVC 2015–2022 二进制兼容，直接用 VS2022 编译即可。

### 3.3. 生成 VS 工程

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Windows\configure.ps1
```

脚本只执行 CMake 配置，不编译，产物为 `build\MeshLab.sln`。它通过 `vswhere -latest` 选择最新安装的 Visual Studio 自带 CMake；找不到时回退到 `PATH` 中的 `cmake`。默认使用 `%USERPROFILE%\Qt\5.15.2\msvc2019_64`，Qt 在其他位置时加 `-QtDir <路径>`。首次配置会联网下载 `src/external/downloads` 下的第三方库；若子模块未初始化，脚本会自动执行 `git submodule update --init --recursive`。

脚本还会自动传入以下在 Windows 上验证过的兼容参数，避免常见编译失败：

- `/utf-8`：避免中文 Windows（ANSI 代码页 936）下第三方源码触发 C4819，进而被 `/WX` 升级为 C2220；
- `-DHAVE_GETTIMEOFDAY=0`：MSVC 没有 `gettimeofday`，同时避免 vcpkg 用户级 MSBuild 集成让 CMake 的探测误判为可用；
- `-DE57_RELEASE_LTO=OFF`：libE57Format 的 `/GL` 目标文件无法被 `cmake -E __create_def` 解析，关闭该库的 LTO 后才能正常导出符号。

配置期间脚本会设置 `VcpkgEnabled=false`，只影响本次 CMake 进程，不会修改用户级 vcpkg 配置。

### 3.4. 编译与运行

1. 用 Visual Studio 2022 打开 `build\MeshLab.sln`，选择 `Release | x64`。
2. 生成 `INSTALL` 目标（它会编译并整理出可运行目录）。
3. 运行 `install\meshlab.exe`。若提示缺少 Qt DLL，把 `%USERPROFILE%\Qt\5.15.2\msvc2019_64\bin` 加入 `PATH`，或执行：

```powershell
& "$env:USERPROFILE\Qt\5.15.2\msvc2019_64\bin\windeployqt.exe" .\install\meshlab.exe
```

> 不要直接运行 `build\src\distrib\Release\meshlab.exe`：VS 是多配置生成器，插件位于 `plugins\Release\`，主程序找不到它们。

### 3.5. 常见问题

| 现象 | 处理方式 |
| --- | --- |
| 找不到 Qt5 | 确认安装的是 Qt 5.15 的 MSVC 2019 64-bit 组件；或传 `-QtDir` 指向实际目录 |
| 找不到 vcglib 头文件 | 执行 `git submodule update --init --recursive` |
| 配置阶段下载失败 | 检查网络与代理后重跑脚本，已下载内容会保留 |
| 编译 lib3mf 时出现 C4819 或 C2220 | 用 `configure.ps1` 重新配置（已加 `/utf-8`）；手动配置时需自行传入相同的编译选项 |
| xerces 报 C3861 找不到 `gettimeofday` | 传入 `-DHAVE_GETTIMEOFDAY=0` 后重新配置；确认 `build\src\external\downloads\xerces-c-3.2.4\config.h` 中该宏为 `#undef` |
| E57Format 链接阶段报 `MSB3073` 或 `__create_def` 错误 | 传入 `-DE57_RELEASE_LTO=OFF` 后重新配置；旧构建目录需重新运行 `configure.ps1` 刷新缓存 |
| 生成时出现 `'pwsh.exe' 不是内部或外部命令` | 来自 vcpkg 的 applocal 步骤，可忽略；彻底消除需禁用 vcpkg 用户级集成 |
| 启动时缺少 Qt DLL | 按 3.4 节配置 `PATH` 或运行 `windeployqt` |

## 4. 分支与 Pull Request

上游用 `main` 存放发布版本、`devel` 存放下一个版本的新功能；缺陷修复和非行为改动提交到 `main`，新功能提交到 `devel`。

本 Fork 的约定：

- `main`：只跟随上游 `main`，不提交定制代码。
- `develop_tora`：个人开发分支，承载全部定制改动；功能开发建议从它创建 `feature/*` 分支，完成后合回。

注意：上游的 `devel` 与本 Fork 的 `develop_tora` 是两个不同的分支。

## 5. 从上游同步到开发分支

建议每月检查一次，或在官方发布重要修复时同步。合并前先提交或暂存未完成的工作。

### 5.1. 更新 main

```powershell
git fetch upstream
git fetch origin
git switch main
git pull --ff-only origin main
git merge --ff-only upstream/main
git push origin main
```

若尚未添加 `upstream`：

```powershell
git remote add upstream https://github.com/cnr-isti-vclab/meshlab.git
```

`--ff-only` 可防止同步分支产生合并提交。失败时不要直接 `git reset --hard` 或强推，先检查分叉原因。

### 5.2. 合并上游更新到 develop_tora

推荐先建同步分支，验证后再合入：

```powershell
git switch develop_tora
git pull --ff-only origin develop_tora
git switch -c sync/upstream-20261103
git merge main
git submodule update --init --recursive
# 编译、启动并做基本回归测试
git push -u origin sync/upstream-20261103
```

随后在 GitHub 创建 PR：`sync/upstream-20261103` → `develop_tora`（日期按实际同步日期替换）。上游更新可能修改 `src/vcglib` 子模块指向，因此 `git submodule update --init --recursive` 不能省略。

### 5.3. 处理合并冲突

```powershell
git status
git diff --name-only --diff-filter=U
```

逐个理解双方改动后手动解决，不要盲目“全部接受当前”或“全部接受传入”。解决后执行：

```powershell
git add <已解决的文件>
git merge --continue
```

要放弃本次未完成的合并，执行 `git merge --abort`。子模块冲突时先确认应使用的子模块提交，再进入子模块核查兼容性，不能仅凭冲突标记自动选版本。

## 6. 仓库结构

- [docs](docs)：生成 MeshLab 文档的 doxygen 脚本；
- `sample` 与 `textures`：测试用的网格与图像；
- [resources](resources)：软件及部署系统使用的资源文件；
- [scripts](scripts)：各平台的构建与部署脚本；
- [src](src)：MeshLab 及其插件的全部源码；
- `unsupported`：已不再参与构建的旧插件。

`src` 下依次是 CMake 辅助脚本（`cmake`）、外部库配置（`external`）、公共工具（`common`）、GUI 与核心（`meshlab`）、插件（`meshlabplugins`）、Windows OpenGL 兼容层（`use_cpu_opengl`）以及 VCGlib 子模块（`vcglib`）。

## 7. 许可证

MeshLab 源码基于 [GPL 许可证](LICENSE.txt) 发布。

## 8. 版权

```text
MeshLab - https://www.meshlab.net
Copyright (C) 2005-2021 Visual Computing Lab, ISTI - Italian National Research Council.
```

## 9. 引用

使用本工具时，请从官网 <https://www.meshlab.net/#references> 列出的文献中选择引用；至少引用：

```bibtex
@software{meshlab,
  author       = {Cignoni, Paolo and Muntoni, Alessandro and Ranzuglia, Guido and Callieri, Marco},
  title        = {MeshLab},
  publisher    = {Zenodo},
  doi          = {10.5281/zenodo.5114037}
}
```

## 10. 联系方式与反馈

- Paolo Cignoni (paolo.cignoni (at) isti.cnr.it)
- Alessandro Muntoni (alessandro.muntoni (at) isti.cnr.it)

可复现的缺陷与功能请求请提交到上游 [GitHub issues](https://github.com/cnr-isti-vclab/meshlab/issues)；使用问题请到 [StackOverflow](http://stackoverflow.com/questions/tagged/meshlab)；本 Fork 定制改动相关的问题请提交到本 Fork 的 [issues](https://github.com/ToraSpencer/meshlab/issues)。
