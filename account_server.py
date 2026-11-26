import json, sqlite3, hashlib, secrets, hmac, os, re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
DB=os.path.join(os.path.dirname(__file__),'accounts.sqlite3')
with sqlite3.connect(DB) as db:
 db.execute('CREATE TABLE IF NOT EXISTS accounts (username TEXT PRIMARY KEY, email TEXT UNIQUE, salt TEXT, password TEXT, character TEXT DEFAULT "")')
 db.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, expires INTEGER)')
def digest(password,salt): return hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
class Handler(BaseHTTPRequestHandler):
 def do_POST(self):
  import time
  try:
   n=int(self.headers.get('Content-Length','0'))
   if not 0<n<=8192: raise ValueError('Invalid request')
   d=json.loads(self.rfile.read(n)); u=str(d.get('username','')).strip().lower(); p=str(d.get('password',''))
   with sqlite3.connect(DB) as db:
    if self.path=='/register':
     e=str(d.get('email','')).strip().lower()
     if not re.fullmatch(r'[a-z0-9_]{3,24}',u) or not 8<=len(p)<=128 or '@' not in e or len(e)>254: raise ValueError('Invalid username, email or password (8+ characters)')
     salt=secrets.token_hex(16); db.execute('INSERT INTO accounts(username,email,salt,password) VALUES(?,?,?,?)',(u,e,salt,digest(p,salt)))
    elif self.path=='/login':
     row=db.execute('SELECT salt,password,character FROM accounts WHERE username=?',(u,)).fetchone()
     if not row or len(p)>128 or not hmac.compare_digest(digest(p,row[0]),row[1]): raise ValueError('Invalid credentials')
     token=secrets.token_urlsafe(32); db.execute('INSERT INTO sessions VALUES(?,?,?)',(token,u,int(time.time())+86400)); return self.reply({'ok':True,'token':token,'character':row[2]})
    elif self.path=='/character':
     row=db.execute('SELECT username FROM sessions WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     name=str(d.get('character','')).strip()
     if not row or not 3<=len(name)<=24 or not all(c.isalnum() or c in '_ ' for c in name): raise ValueError('Invalid session or character name')
     db.execute('UPDATE accounts SET character=? WHERE username=?',(name,row[0]))
    else: raise ValueError('Unknown endpoint')
   self.reply({'ok':True})
  except sqlite3.IntegrityError: self.reply({'ok':False,'error':'Account already exists'})
  except (ValueError,TypeError,AttributeError) as e: self.reply({'ok':False,'error':str(e)})
 def reply(self,d):
  b=json.dumps(d).encode(); self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
if __name__=='__main__':
 print('Account test server: port 8080. Private network only.',flush=True); ThreadingHTTPServer(('0.0.0.0',8080),Handler).serve_forever()
