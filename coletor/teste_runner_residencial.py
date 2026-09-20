#!/usr/bin/env python3
"""Portões estáticos do runner residencial; não registra runner nem coleta."""

from pathlib import Path
import os
import plistlib
import subprocess
import tempfile


RAIZ = Path(__file__).resolve().parents[1]
PASTA = RAIZ / "ferramentas" / "runner_residencial"


def provar_recusa_de_atualizacao_durante_janela():
    with tempfile.TemporaryDirectory(prefix="canario-runner-teste-") as tmp:
        temporario = Path(tmp)
        binarios = temporario / "bin"
        binarios.mkdir()
        launchctl = binarios / "launchctl"
        launchctl.write_text(
            "#!/bin/bash\n"
            "if [ \"${1:-}\" = print ]; then\n"
            "  printf 'state = running\\n'\n"
            "  exit 0\n"
            "fi\n"
            "exit 99\n",
            encoding="utf-8",
        )
        launchctl.chmod(0o700)

        ambiente = os.environ.copy()
        ambiente["HOME"] = str(temporario / "home")
        ambiente["PATH"] = "{}:/usr/bin:/bin:/usr/sbin:/sbin".format(binarios)
        resultado = subprocess.run(
            ["/bin/bash", str(PASTA / "instalar.sh")],
            check=False,
            capture_output=True,
            text=True,
            env=ambiente,
        )
        assert resultado.returncode == 1
        assert "runner residencial esta executando uma janela" in resultado.stdout
        assert not (temporario / "home/.canario/runner-residencial/runner.sh").exists()


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
        'kill -0 "$LISTENER_PID"',
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
    assert "RECUSADO: o runner residencial esta executando uma janela" in instalar
    assert "runner_permanente_em_execucao" in instalar
    assert instalar.index('"$AQUI/runner.sh" --check') < instalar.index(
        'install -m 700 "$AQUI/runner.sh"')
    assert instalar.index('launchctl bootout "$DOMINIO/$LABEL"') < instalar.index(
        'install -m 700 "$AQUI/runner.sh"')
    assert "launchctl bootstrap" in instalar
    assert "--check" in instalar
    assert "launchctl bootout" in remover
    assert "gh workflow" not in remover

    provar_recusa_de_atualizacao_durante_janela()

    print("ok: runner duravel espera agendas, falha fechado e nao duplica coleta")


if __name__ == "__main__":
    main()
