# CUDA 13.2 用户态 runtime

本发布不替换系统 CUDA，也不安装 NVIDIA 驱动。板端进程通过
`LD_LIBRARY_PATH` 优先加载一份隔离的 CUDA 13.2 用户态库：

```text
/brand_data/ai_workspace/thor01-cu132-20261022/
  runtime/lib/{libcudart.so.13,libcublas.so.13,libcublasLt.so.13}
  compat/compat_orin/{libcuda.so.1.1,libnvidia-nvvm70.so,libnvidia-ptxjitcompiler.so,...}
```

`run-8080-cu130rt132.sh` 和 `run-8082-cu130rt132.sh` 设置：

```bash
export LD_LIBRARY_PATH=$BASE/compat/compat_orin:$BASE/runtime/lib
```

系统 `/usr/local/cuda`、系统 `libcuda`、系统驱动和系统环境变量都不改。

## 1. 必需文件和校验值

实测 board 上的文件：

| 文件 | SHA256 |
|---|---|
| `runtime/lib/libcudart.so.13` | `17515a9dd5f56015baac7a7d94617e87ad802345ced2248fa37c4b5d1fd88235` |
| `runtime/lib/libcublas.so.13` | `f0993dea3451082be0e2c780f68600b27688dbea364c7031ae77e16ab3f9ed8c` |
| `runtime/lib/libcublasLt.so.13` | `5af2ae59e652871dfc32fda727c0ede03fce740ca8c06b38b28a59644b35b247` |
| `compat/compat_orin/libcuda.so.1.1` | `e4c849be8e1bca055c13c8ee0866abfbc58a7041db32c9534ea07853da4f801d` |

版本身份：

- `libcudart.so.13`：`nvidia-cuda-runtime 13.2.86`
- `libcublas.so.13` / `libcublasLt.so.13`：`nvidia-cublas 13.2.2.2`
- compat：`cuda-compat-orin-13-2_13.2.44290101-1_arm64.deb`
- 实测 `cudaRuntimeGetVersion() = 13020`，`cuDriverGetVersion() = 13020`

## 2. 官方来源

以下是本机实际使用的 NVIDIA 官方下载地址和 SHA256，不是从第三方镜像取的。

### runtime wheel

```text
https://files.pythonhosted.org/packages/89/d4/fa981071e3d9f29158ca16c69ee617831cd6df4dd47024149c16eec717f8/nvidia_cuda_runtime-13.2.86-py3-none-manylinux2014_aarch64.manylinux_2_17_aarch64.whl
37844957894bfdecf90243568d21a2cb251b66106915b71459a23c8e6ef2da69
```

### cuBLAS wheel

```text
https://files.pythonhosted.org/packages/3e/03/a5159a114b62d738d385233be6ea345bb43e1f6392fabaebca61c96ed283/nvidia_cublas-13.2.2.2-py3-none-manylinux_2_27_aarch64.whl
178c9d61959c1184603951703c947b2007989cf7fea6b216cf1a31c104fbdeac
```

### cuda-compat-orin

```text
https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/sbsa/cuda-compat-orin-13-2_13.2.44290101-1_arm64.deb
3331f3ac94eecc0e3c0d1976c8fa306c2bf33dd6f771e0d61bb583cab3590037
```

发布包不依赖作者宿主的 wheel 缓存；上面的 URL 和 SHA256 就是完整下载身份。
如果组织内已有镜像，只需保证下载文件哈希一致，不要把缓存目录写进部署脚本。

## 3. 一键获取并展开

在任意有 `curl`、`python3`、`dpkg-deb` 的 Linux 机器上：

```bash
./scripts/fetch-cu132-runtime.sh ./cu132-runtime
```

如果已经在本地保存了三件下载文件，可用 `CU132_CACHE` 指向该目录，跳过联网：

```bash
CU132_CACHE=/path/to/cache ./scripts/fetch-cu132-runtime.sh ./cu132-runtime
```

脚本会下载上述三件、校验 SHA256，并生成：

```text
cu132-runtime/
  runtime/lib/libcudart.so.13
  runtime/lib/libcublas.so.13
  runtime/lib/libcublasLt.so.13
  compat/compat_orin/...
```

如需手工展开 wheel：

```bash
python3 -m zipfile -e nvidia_cuda_runtime-13.2.86-*.whl runtime-wheel
python3 -m zipfile -e nvidia_cublas-13.2.2.2-*.whl cublas-wheel
cp runtime-wheel/nvidia/cu13/lib/libcudart.so.13 runtime/lib/
cp cublas-wheel/nvidia/cu13/lib/libcublas*.so.13 runtime/lib/
dpkg-deb -x cuda-compat-orin-13-2_*.deb compat-root
cp -a compat-root/usr/local/cuda-13.2/compat_orin/. compat/compat_orin/
```

## 4. 传到 Thor01

如果目标板还没有 runtime：

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
ssh nvidia@192.168.1.101 "mkdir -p $BASE/runtime/lib $BASE/compat/compat_orin"
rsync -a cu132-runtime/runtime/lib/ nvidia@192.168.1.101:$BASE/runtime/lib/
rsync -a cu132-runtime/compat/compat_orin/ nvidia@192.168.1.101:$BASE/compat/compat_orin/
```

Thor01 当前已经有这份隔离 runtime；升级时不要用新 runtime 覆盖其他生产目录。

## 5. 验证

```bash
BASE=/brand_data/ai_workspace/thor01-cu132-20261022
sha256sum \
  $BASE/runtime/lib/libcudart.so.13 \
  $BASE/runtime/lib/libcublas.so.13 \
  $BASE/runtime/lib/libcublasLt.so.13 \
  $BASE/compat/compat_orin/libcuda.so.1.1

LD_LIBRARY_PATH=$BASE/compat/compat_orin:$BASE/runtime/lib \
  ldd $BASE/bin/llama-server-cu130rt132-sm110a | grep -E 'cuda|cublas'

python3 scripts/device_probe.py
```

`ldd` 必须显示 13.2 目录中的 `libcudart/libcublas/libcublasLt` 和
`compat_orin/libcuda.so.1`，不能显示 `not found`，也不能回落到系统 12.8 库。

实测 `device_probe.py` 输出：

```text
devices=1 name=Thor cc=11.0 cc_code=1100 runtime=13020 driver=13020
T4_GUARD=NOT_MATCHED expected_cc_code=1010
```

这里的 `cc=11.0` 是 CUDA 13.2 compat 上报的 SM 版本；生产 T4 门常量为
`10.1a = 1010`。因此 T4 快路在本组合下不生效。不要通过修改守卫常量来“让它命中”；
本轮没有验证 T4 在 13.2 compat 下的正确性。

## 6. 许可和边界

NVIDIA runtime 库是 NVIDIA 的专有软件，不进入本发布包；请按 NVIDIA CUDA 许可从
官方地址获取。发布包只包含 llama.cpp MIT 代码/补丁、由本机构建的二进制、脚本和证据。
