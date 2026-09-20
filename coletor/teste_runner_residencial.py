#!/usr/bin/env python3
"""Portões estáticos do runner residencial; não registra runner nem coleta."""

from pathlib import Path
import plistlib
import subprocess


RAIZ = Path(__file__).resolve().parents[1]
PASTA = RAIZ / "ferramentas" / "runner_residencial"


def main():
    runner = (PASTA / "runner.sh").read_text(encoding="utf-8")
    instalar = (PASTA / "instalar.sh").read_text(encoding="utf-8")
    remover = (PASTA / "desinstalar.sh").read_text(encoding="utf-8")
    plist = (PASTA / "br.com.canario.runner-residencial.plist.in").read_bytes()

    for script in ("runner.sh", "instalar.sh", "desinstalar.sh"):
        subprocess.run(["bash", "-n", str(PASTA / script)], check=True)

    config = plistlib.loads(plist)
    assert config["Label"] == "br.com.canario.runner-residencial"
    assert config["StartCalendarInterval"] == {"Hour": 2, "Minute": 50}
    assert config["ProgramArguments"][:3] == [
        "/usr/bin/caffeinate", "-is", "/bin/bash"]
    assert config["ProgramArguments"][3].endswith(
        "/.canario/runner-residencial/runner.sh")

    exigidos = (
        "actions/runners/registration-token",
        "RUNNER_SHA256=",
        "shasum -a 256 -c -",
        "--proto '=https'",
        "--labels sempre-ligado,xcode",
        'obter_run_nova "$WORKFLOW_PIPELINE" schedule',
        "cota chegou a $cota_pct%",
        'gh workflow disable "$WORKFLOW_PIPELINE"',
        'gh workflow disable "$WORKFLOW_CANDIDATO"',
        "adquirir_lock",
        "limpar_registros_orfaos",
        "listener_local_ativo",
        'rm -f -- "$LOCK/pid"',
        'rmdir "$LOCK"',
    )
    for trecho in exigidos:
        assert trecho in runner, "proteção ausente: {}".format(trecho)

    proibidos = (
        "EXPIRA_UTC", "auto_remover", "sonda-significado.yml",
        'gh workflow run "$WORKFLOW_PIPELINE"',
        'gh workflow run "$WORKFLOW_CANDIDATO"',
    )
    for trecho in proibidos:
        assert trecho not in runner, "comportamento proibido: {}".format(trecho)

    assert "LABEL_TEMPORARIO" in instalar
    assert "RECUSADO: o supervisor temporario ainda esta instalado" in instalar
    assert "launchctl bootstrap" in instalar
    assert "--check" in instalar
    assert "launchctl bootout" in remover
    assert "gh workflow" not in remover

    print("ok: runner duravel espera agendas, falha fechado e nao duplica coleta")


if __name__ == "__main__":
    main()
