#!/usr/bin/env python3
"""Redefine a senha de uma conta local LolPRO sem apagar personagem ou progresso."""
import getpass
import hashlib
import os
import secrets
import sqlite3
import sys

DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "accounts.sqlite3")

def main():
    if not os.path.exists(DB):
        print("Banco accounts.sqlite3 nao encontrado nesta pasta.")
        print("Coloque este script ao lado do banco de dados usado pelo servidor.")
        input("Pressione Enter para sair...")
        return 1

    username = input("Usuario da conta: ").strip().lower()
    if not username:
        print("Usuario vazio.")
        return 1

    password = getpass.getpass("Nova senha (minimo 8 caracteres): ")
    confirm = getpass.getpass("Repita a nova senha: ")
    if len(password) < 8 or len(password) > 128:
        print("A senha precisa ter entre 8 e 128 caracteres.")
        return 1
    if password != confirm:
        print("As senhas nao conferem.")
        return 1

    salt = secrets.token_hex(16)
    hashed = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), 600000).hex()

    with sqlite3.connect(DB) as db:
        row = db.execute("SELECT username, character FROM accounts WHERE username=?", (username,)).fetchone()
        if row is None:
            print("Conta nao encontrada. Nenhuma alteracao foi feita.")
            return 1
        db.execute("UPDATE accounts SET salt=?, password=? WHERE username=?", (salt, hashed, username))
        db.commit()

    print("Senha redefinida com sucesso para:", username)
    print("Personagem preservado:", row[1] or "(nenhum personagem salvo)")
    print("Agora entre no jogo com a nova senha.")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except sqlite3.Error as exc:
        print("Erro no banco de dados:", exc)
        sys.exit(1)
