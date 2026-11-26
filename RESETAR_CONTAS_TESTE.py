import os
import shutil
import sqlite3
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, "accounts.sqlite3")

print("LOLPRO-ON - RESETAR CONTAS DE TESTE")
print("Este processo apaga todas as contas, sessoes e personagens desta base local.")
if not os.path.exists(DB):
    print("Nenhum banco accounts.sqlite3 foi encontrado nesta pasta.")
    input("Pressione Enter para sair...")
    raise SystemExit(0)

confirm = input("Digite APAGAR para confirmar: ").strip()
if confirm != "APAGAR":
    print("Cancelado. Nada foi alterado.")
    input("Pressione Enter para sair...")
    raise SystemExit(0)

backup = DB + ".backup-" + datetime.now().strftime("%Y%m%d-%H%M%S")
shutil.copy2(DB, backup)

try:
    with sqlite3.connect(DB) as db:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("BEGIN IMMEDIATE")
        db.execute("DELETE FROM sessions")
        db.execute("DELETE FROM accounts")
        db.commit()
    print("Contas, personagens e sessoes apagados com sucesso.")
    print("Backup preservado em:", backup)
except Exception:
    shutil.copy2(backup, DB)
    print("Falha ao limpar o banco. O backup foi restaurado.")
    raise

input("Pressione Enter para sair...")
