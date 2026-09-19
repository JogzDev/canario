"""Mutações do workflow: um gate escrito mas pulado não protege o painel."""

from copy import deepcopy
from pathlib import Path

import yaml

from teste_workflows import checar_portao_publicacao


def main():
    caminho = Path(__file__).resolve().parents[1] / ".github/workflows/pipeline-diario.yml"
    original = yaml.safe_load(caminho.read_text(encoding="utf-8"))["jobs"]
    assert not checar_portao_publicacao(original)

    def portao(jobs):
        return next(p for p in jobs["publicacao"]["steps"]
                    if "sonda_significado_publico.py" in p.get("run", ""))

    def alerta(jobs):
        return next(p["env"] for p in jobs["alerta"]["steps"]
                    if "ESTADO_DO_PIPELINE" in p.get("env", {}))

    mutacoes = [
        lambda j: j.pop("publicacao"),
        lambda j: j["publicacao"].update(needs=["motor"]),
        lambda j: j["publicacao"].update({"if": "${{ success() }}"}),
        lambda j: j["publicacao"].update({"continue-on-error": True}),
        lambda j: portao(j).update({"continue-on-error": True}),
        lambda j: portao(j).update({"if": "false"}),
        lambda j: portao(j).update(run=portao(j)["run"].replace("--exigir-publicacao", "")),
        lambda j: portao(j)["env"].update(DATA_OPERACIONAL="2026-09-02"),
        lambda j: portao(j)["env"].pop("SUPABASE_PUBLISHABLE_KEY"),
        lambda j: portao(j)["env"].update(SUPABASE_SECRET_KEY="nao-usar"),
        lambda j: j["publicacao"]["steps"][-1].pop("if"),
        lambda j: j["alerta"]["needs"].remove("publicacao"),
        lambda j: alerta(j).update(ESTADO_DO_PIPELINE="verde"),
        lambda j: alerta(j).update(JOBS_QUE_FALHARAM="motor=success"),
    ]
    for indice, mutar in enumerate(mutacoes, 1):
        jobs = deepcopy(original)
        mutar(jobs)
        assert checar_portao_publicacao(jobs), "mutação {} passou".format(indice)
    print("ok: {} regressões do gate público são rejeitadas".format(len(mutacoes)))


if __name__ == "__main__":
    main()
