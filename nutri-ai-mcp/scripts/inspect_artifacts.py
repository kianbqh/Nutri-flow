import os
import torch
from tensorboard.backend.event_processing.event_accumulator import EventAccumulator


def inspect_run(run_name: str, run_dir: str) -> None:
    print("\n" + "=" * 70)
    print(f"RUN: {run_name}")
    print(f"DIR: {run_dir}")

    ckpt_path = os.path.join(run_dir, "best_model.pth")
    if os.path.exists(ckpt_path):
        state_dict = torch.load(ckpt_path, map_location="cpu")
        total_params = sum(v.numel() for v in state_dict.values() if hasattr(v, "numel"))
        print(f"[CHECKPOINT] {ckpt_path}")
        print(f"[CHECKPOINT] tensors: {len(state_dict)}")
        print(f"[CHECKPOINT] total params: {total_params}")
        print(f"[CHECKPOINT] first keys: {list(state_dict.keys())[:5]}")
    else:
        print("[CHECKPOINT] not found")

    event_file = None
    for root, _, files in os.walk(run_dir):
        for file_name in files:
            if file_name.startswith("events.out.tfevents"):
                event_file = os.path.join(root, file_name)
                break
        if event_file:
            break

    if event_file is None:
        print("[EVENTS] not found")
        return

    print(f"[EVENTS] {event_file}")
    event_acc = EventAccumulator(event_file)
    event_acc.Reload()
    scalar_tags = event_acc.Tags().get("scalars", [])
    print(f"[EVENTS] scalar tags: {scalar_tags}")
    for tag in scalar_tags:
        values = event_acc.Scalars(tag)
        if values:
            last = values[-1]
            print(f"[EVENTS] {tag}: last_step={last.step}, last_value={last.value:.6f}")


if __name__ == "__main__":
    project_root = "G:/GraduationProj_Nutri-flow/Nutri-flow/nutri-ai-mcp"
    inspect_run("swin_tiny_smoke", os.path.join(project_root, "weights_smoke_tiny_gt"))
    inspect_run("swin_base_smoke", os.path.join(project_root, "weights_smoke_base_gt"))
