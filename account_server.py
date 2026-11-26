import base64, binascii, json, sqlite3, hashlib, secrets, hmac, os, re, math, threading, time
players = {}
voice_queues = {}
voice_last = {}
world_lock = threading.Lock()
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
DB=os.path.join(os.path.dirname(__file__),'accounts.sqlite3')
with sqlite3.connect(DB) as db:
 db.execute('CREATE TABLE IF NOT EXISTS accounts (username TEXT PRIMARY KEY, email TEXT UNIQUE, salt TEXT, password TEXT, character TEXT DEFAULT "")')
 db.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, expires INTEGER)')
with sqlite3.connect(DB) as db:
 db.execute('CREATE TABLE IF NOT EXISTS characters (username TEXT, slot INTEGER, name TEXT, PRIMARY KEY(username,slot))')
 db.execute('INSERT OR IGNORE INTO characters SELECT username,0,character FROM accounts WHERE character != ""')
def digest(password,salt): return hashlib.pbkdf2_hmac('sha256',password.encode(),bytes.fromhex(salt),600000).hex()
class Handler(BaseHTTPRequestHandler):
 def do_GET(self):
  self.reply({'ok':True,'service':'LolPRO-ON','world_protocol':2})
 def do_POST(self):
  import time
  try:
   n=int(self.headers.get('Content-Length','0'))
   if not 0<n<=(24000 if self.path=='/voice' else 8192): raise ValueError('Invalid request')
   d=json.loads(self.rfile.read(n)); u=str(d.get('username','')).strip().lower(); p=str(d.get('password',''))
   with sqlite3.connect(DB) as db:
    if self.path=='/register':
     e=str(d.get('email','')).strip().lower()
     if not re.fullmatch(r'[a-z0-9_]{3,24}',u) or not 8<=len(p)<=128 or '@' not in e or len(e)>254: raise ValueError('Invalid username, email or password (8+ characters)')
     salt=secrets.token_hex(16); db.execute('INSERT INTO accounts(username,email,salt,password) VALUES(?,?,?,?)',(u,e,salt,digest(p,salt)))
    elif self.path=='/login':
     row=db.execute('SELECT salt,password,character FROM accounts WHERE username=?',(u,)).fetchone()
     if not row or len(p)>128 or not hmac.compare_digest(digest(p,row[0]),row[1]): raise ValueError('Invalid credentials')
     token=secrets.token_urlsafe(32); db.execute('INSERT INTO sessions VALUES(?,?,?)',(token,u,int(time.time())+86400)); return self.reply({'ok':True,'token':token,'character':row[2],'characters':[{'slot':i,'name':name} for i,name in db.execute('SELECT slot,name FROM characters WHERE username=? ORDER BY slot',(u,))]})
    elif self.path=='/voice':
     row=db.execute('SELECT username FROM sessions WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     if not row: raise ValueError('Invalid session')
     uid=row[0]; now=time.monotonic()
     audio=d.get('audio','')
     if not isinstance(audio,str) or len(audio)>18000: raise ValueError('Invalid audio')
     try: raw=base64.b64decode(audio,validate=True)
     except binascii.Error: raise ValueError('Invalid audio')
     if len(raw)>12800 or len(raw)%2: raise ValueError('Invalid audio')
     with world_lock:
      for key in list(voice_queues):
       if key not in players or now-players[key]['seen']>15:
        voice_queues.pop(key,None); voice_last.pop(key,None)
      me=players.get(uid)
      if not me or now-me['seen']>15: return self.reply({'ok':True,'packets':[]})
      if now-voice_last.get(uid,-100)<0.09: return self.reply({'ok':True,'packets':[]})
      voice_last[uid]=now
      if raw:
       for key,target in players.items():
        if key==uid or now-target['seen']>15 or now-voice_last.get(key,-100)>3: continue
        if math.dist(me['pos'],target['pos'])<=20:
         q=voice_queues.setdefault(key,[])
         q.append({'id':uid,'name':me['name'],'audio':audio,'time':now})
         del q[:-12]
      packets=[{k:v for k,v in item.items() if k!='time'} for item in voice_queues.pop(uid,[]) if now-item['time']<1.5]
     return self.reply({'ok':True,'packets':packets})
    elif self.path=='/world':
     row=db.execute('SELECT accounts.username, accounts.character FROM sessions JOIN accounts ON sessions.username=accounts.username WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     if not row or not row[1]: raise ValueError('Invalid session or character')
     pos=d.get('pos')
     angle=d.get('angle')
     state=d.get('state')
     if not isinstance(pos,list) or len(pos)!=3 or not all(type(v) in (int,float) and math.isfinite(v) and abs(v)<=150 for v in pos) or type(angle) not in (int,float) or not math.isfinite(angle) or state not in ('Idle','Walking','Running','Jumping'): raise ValueError('Invalid movement')
     now=time.monotonic()
     with world_lock:
      for key in list(players):
       if now-players[key]['seen']>15: del players[key]
      me=players.setdefault(row[0],{'id':row[0],'hp':100,'last_attack':-100,'attack_seq':'','respawn_at':0,'generation':0,'potions':5,'potion_seq':''})
      if me['hp']==0 and now>=me['respawn_at']:
       me['hp']=100; me['generation']+=1
      if d.get('generation',0)!=me['generation']: pos=[0,0.1,0]
      me.update(name=row[1],pos=pos,angle=angle,state=state,seen=now)
      seq=str(d.get('attack',''))[:80]
      if seq and seq!=me['attack_seq']:
       me['attack_seq']=seq
       if me['hp']>0 and now-me['last_attack']>=0.6:
        me['last_attack']=now
        for key,target in players.items():
         if key==row[0] or target['hp']<=0: continue
         dx,dy,dz=[target['pos'][i]-pos[i] for i in range(3)]
         dist=math.sqrt(dx*dx+dy*dy+dz*dz)
         if 0.01<dist<=2.0 and (dx*math.sin(angle)+dz*math.cos(angle))/dist>0.3:
          target['hp']=max(0,target['hp']-10)
          if target['hp']==0: target['respawn_at']=now+3
      potion=str(d.get('potion',''))[:80]
      if potion and potion!=me['potion_seq']:
       me['potion_seq']=potion
       if 0<me['hp']<100 and me['potions']>0:
        me['potions']-=1; me['hp']=min(100,me['hp']+20)
      others=[{k:item[k] for k in ('id','name','pos','angle','state','hp','attack_seq')} for key,item in players.items() if key!=row[0]]
      own={k:me[k] for k in ('hp','generation','potions','attack_seq','potion_seq')}
     return self.reply({'ok':True,'players':others,'self':own})
    elif self.path=='/character':
     row=db.execute('SELECT username FROM sessions WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     name=str(d.get('character','')).strip()
     if not row or not 3<=len(name)<=24 or not all(c.isalnum() or c in '_ ' for c in name): raise ValueError('Invalid session or character name')
     slot=d.get('slot',0)
     if type(slot) is not int or not 0<=slot<4: raise ValueError('Invalid slot')
     existing=db.execute('SELECT name FROM characters WHERE username=? AND slot=?',(row[0],slot)).fetchone()
     if existing and existing[0]!=name: raise ValueError('Slot already occupied')
     db.execute('INSERT OR IGNORE INTO characters VALUES(?,?,?)',(row[0],slot,name))
     db.execute('UPDATE accounts SET character=? WHERE username=?',(name,row[0]))
    else: raise ValueError('Unknown endpoint')
   self.reply({'ok':True})
  except sqlite3.IntegrityError: self.reply({'ok':False,'error':'Account already exists'})
  except (ValueError,TypeError,AttributeError) as e: self.reply({'ok':False,'error':str(e)})
 def reply(self,d):
  b=json.dumps(d).encode(); self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
def discovery():
 import socket
 with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
  sock.bind(('0.0.0.0',8081))
  while True:
   data,addr=sock.recvfrom(256)
   if data==b'LOLPRO_DISCOVER_V1':
    sock.sendto(b'LOLPRO_SERVER_V1',addr)
if __name__=='__main__':
 import threading
 threading.Thread(target=discovery,daemon=True).start()
 print('Account test server: port 8080. Private network only.',flush=True); ThreadingHTTPServer(('0.0.0.0',int(os.environ.get('PORT','8080'))),Handler).serve_forever()
