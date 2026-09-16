#!/usr/bin/env python3
"""裁剪吴语方案里的大词库：只保留「能被预设词库 essay.txt 解析出码表」的词条。

原因：luna_pinyin.sogou.dict.yaml 有 103 万条无码表的词，其中只有约 9 万条能在
essay.txt 预设词库中查到码表；其余 94 万条在 rime 部署时拿不到码表、无法参与输入，
却要陪着一起解析与建表，导致手机端首次部署耗时数分钟并最终被系统杀掉。
裁剪后功能不变（那些词本来就打不出来），部署负担下降约 11 倍。
"""
import pathlib
import sys

CPP = pathlib.Path(__file__).resolve().parents[1] / "plugin/rime/src/main/cpp"
ESSAY = CPP / "rime-essay/essay.txt"
TARGETS = [
    CPP / "rime-wugniu-suwu/luna_pinyin.sogou.dict.yaml",
    CPP / "rime-wugniu-suwu/sougouciku.dict.yaml",
]

def load_vocab() -> set:
    vocab = set()
    for line in ESSAY.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 2 and parts[1].strip():
            vocab.add(parts[0])
    return vocab

def main() -> int:
    if not ESSAY.exists():
        print(f"找不到预设词库 {ESSAY}", file=sys.stderr)
        return 1
    vocab = load_vocab()
    print(f"预设词库词条数: {len(vocab)}")
    for target in TARGETS:
        if not target.exists():
            print(f"跳过（不存在）: {target}")
            continue
        lines = target.read_text(encoding="utf-8", errors="replace").splitlines()
        try:
            sep = lines.index("...")
        except ValueError:
            sep = 0
        head, body = lines[: sep + 1], lines[sep + 1 :]
        kept = [l for l in body if l.strip() and l.split("\t")[0] in vocab]
        dropped = sum(1 for l in body if l.strip()) - len(kept)
        target.write_text("\n".join(head + kept) + "\n", encoding="utf-8")
        print(f"{target.name}: 保留 {len(kept)} 条，丢弃 {dropped} 条")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
