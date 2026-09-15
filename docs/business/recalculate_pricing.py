"""Reproduce proposed pricing arithmetic without network calls or purchases."""
from pathlib import Path
import csv
import json
from decimal import Decimal as D

ROOT = Path(__file__).resolve().parent
model = json.loads((ROOT / "pricing-model-2026-09-09.json").read_text(), parse_float=D)
ops = {o["id"]: o for o in model["operations"]}
workflow_tokens = sum(ops[k]["tokens"] * n for k, n in model["standard_workflow"].items())
workflow_cost = sum(ops[k]["variable_cost"] * n for k, n in model["standard_workflow"].items())
cost_bound = max(o["variable_cost"] / o["tokens"] for o in ops.values())
assert workflow_tokens == 100 and workflow_cost == D("1.14")
assert cost_bound == D("0.012")
rows = []
for plan in model["plans"]:
    for channel in model["scenarios"]:
        if channel["channel"] != plan["channel"]:
            continue
        p = plan["price"]
        net = p * (1 - channel["percentage_fee"]) - channel["fixed_fee"]
        reserve = p * model["reserve_fraction_of_gross"]
        full = plan["tokens"] // workflow_tokens
        typical = full * workflow_cost
        worst = plan["tokens"] * cost_bound
        for usage, cost in [("full_standard_workflows", typical), ("all_tokens_cost_bound", worst), ("double_cost_stress", 2 * worst)]:
            contribution = net - reserve - cost
            rows.append({"plan":plan["id"],"scenario":channel["id"],"usage":usage,
                "gross_usd":p,"tokens":plan["tokens"],"standard_workflows":full,
                "concepts_in_workflows":3*full,"models_in_workflows":full,
                "remaining_tokens_after_workflows":plan["tokens"]%workflow_tokens,
                "net_after_payment_fee":net,"operating_reserve":reserve,
                "assumed_variable_cost":cost,"contribution_usd":contribution,
                "contribution_pct_gross":contribution / p * 100,
                "contribution_pct_net":contribution / net * 100})
out = ROOT / "pricing-scenarios-2026-09-09.csv"
with out.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    for row in rows:
        writer.writerow({k: str(v.quantize(D("0.0001"))) if isinstance(v,D) else v for k,v in row.items()})
weekly = next(r for r in rows if r["plan"]=="ios_weekly" and r["scenario"]=="apple_30" and r["usage"]=="all_tokens_cost_bound")
assert weekly["contribution_usd"] == D("1.5935")
print(f"Validated {len(rows)} scenarios. Standard workflow: {workflow_tokens} Tokens, assumed ${workflow_cost} cost.")
print(f"$7.99 weekly / Apple 30% / full cost bound: contribution ${weekly['contribution_usd']}; net margin {weekly['contribution_pct_net']:.2f}%.")
print(out)
