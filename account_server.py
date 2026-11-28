import base64, binascii, json, sqlite3, hashlib, secrets, hmac, os, re, math, threading, time
players = {}
voice_queues = {}
voice_last = {}
world_lock = threading.Lock()
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
DATABASE_URL=os.environ.get('DATABASE_URL','').strip()
DB=os.environ.get('LOLPRO_DB_PATH') or os.path.join(os.path.dirname(__file__),'accounts.sqlite3')
from contextlib import contextmanager, closing
integrity_errors=(sqlite3.IntegrityError,)
database_errors=(sqlite3.Error,)
if DATABASE_URL:
 import psycopg
 from psycopg_pool import ConnectionPool
 integrity_errors+=(psycopg.IntegrityError,)
 database_errors+=(psycopg.Error,)
 pool=ConnectionPool(DATABASE_URL,kwargs={'sslmode':'require','connect_timeout':10},min_size=1,max_size=4,open=False)
 pool.open(wait=True,timeout=30)
 class PostgresDB:
  def __init__(self,conn): self.conn=conn
  def execute(self,sql,params=()):
   sql=sql.replace('?', '%s').replace('""', "''")
   if sql.startswith('INSERT OR IGNORE INTO '):
    sql=sql.replace('INSERT OR IGNORE INTO ','INSERT INTO ',1)+' ON CONFLICT DO NOTHING'
   elif sql.startswith('INSERT OR REPLACE INTO '):
    table=sql.split()[4]
    keys,field={'admins':('username','permissions'),'upgrades':('username,slot,kind','rank'),'gear':('username,slot,kind','equipped'),'session_slots':('token','slot'),'avatar_profiles':('username,slot','avatar'),'character_positions':('username,slot','x,y,z,angle')}[table]
    assignments=','.join(f'{col}=EXCLUDED.{col}' for col in field.split(','))
    sql=sql.replace('INSERT OR REPLACE INTO ','INSERT INTO ',1)+f' ON CONFLICT ({keys}) DO UPDATE SET {assignments}'
   return self.conn.execute(sql,params)
  def commit(self): self.conn.commit()
else:
 os.makedirs(os.path.dirname(os.path.abspath(DB)),exist_ok=True)
@contextmanager
def connect_db():
 if DATABASE_URL:
  with pool.connection() as conn:
   yield PostgresDB(conn)
 else:
  with closing(sqlite3.connect(DB)) as conn:
   with conn:
    yield conn
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS accounts (username TEXT PRIMARY KEY, email TEXT UNIQUE, salt TEXT, password TEXT, character TEXT DEFAULT "")')
 db.execute('CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, username TEXT, expires INTEGER)')
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS characters (username TEXT, slot INTEGER, name TEXT, PRIMARY KEY(username,slot))')
 db.execute('INSERT OR IGNORE INTO characters SELECT username,0,character FROM accounts WHERE character != ""')
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS progress (username TEXT, slot INTEGER, level INTEGER DEFAULT 1, xp INTEGER DEFAULT 0, coins INTEGER DEFAULT 100, potions INTEGER DEFAULT 5, weapon INTEGER DEFAULT 0, armor INTEGER DEFAULT 0, PRIMARY KEY(username,slot))')
 db.execute('CREATE TABLE IF NOT EXISTS character_positions (username TEXT, slot INTEGER, x REAL, y REAL, z REAL, angle REAL, PRIMARY KEY(username,slot))')
 db.execute('CREATE TABLE IF NOT EXISTS world_presence (username TEXT PRIMARY KEY, slot INTEGER, payload TEXT, seen DOUBLE PRECISION)')
 db.execute('CREATE TABLE IF NOT EXISTS session_slots (token TEXT PRIMARY KEY, slot INTEGER)')
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS gear (username TEXT, slot INTEGER, kind TEXT, equipped INTEGER DEFAULT 0, PRIMARY KEY(username,slot,kind))')
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS upgrades (username TEXT, slot INTEGER, kind TEXT, rank INTEGER DEFAULT 1, PRIMARY KEY(username,slot,kind))')
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS class_profiles (username TEXT, slot INTEGER, class TEXT, gender TEXT, PRIMARY KEY(username,slot))')
with connect_db() as db:
 db.execute("CREATE TABLE IF NOT EXISTS avatar_profiles (username TEXT, slot INTEGER, avatar TEXT DEFAULT 'whiteclown', PRIMARY KEY(username,slot))")
 db.execute("UPDATE avatar_profiles SET avatar='whiteclown' WHERE avatar IN ('erika_archer','maria')")
 db.execute("UPDATE class_profiles SET gender='Masculino' WHERE gender='Feminino'")
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS admins (username TEXT PRIMARY KEY, permissions TEXT)')
 db.execute('CREATE TABLE IF NOT EXISTS admin_audit (username TEXT, command TEXT, created INTEGER)')
 db.execute('CREATE TABLE IF NOT EXISTS bans (username TEXT PRIMARY KEY)')
with connect_db() as db:
 db.execute('CREATE TABLE IF NOT EXISTS pets (username TEXT, slot INTEGER, level INTEGER DEFAULT 1, xp INTEGER DEFAULT 0, mission INTEGER DEFAULT 0, summoned INTEGER DEFAULT 0, PRIMARY KEY(username,slot))')
def pet_bonuses(pet):
 if not pet.get('summoned',False): return (0,0,0)
 lv=max(1,min(99,int(pet.get('level',1))))
 return (5+(lv-1)//4,3+(lv-1)//5,50+(lv-1)*2)
def admin_permissions(db,u):
 owner=os.environ.get('LOLPRO_OWNER','').strip().lower()
 if owner and u==owner: return ['owner','curar','nivel','dinheiro','adm','removeradm','ban','desban']
 row=db.execute('SELECT permissions FROM admins WHERE username=?',(u,)).fetchone()
 return json.loads(row[0]) if row else []
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
   with connect_db() as db:
    if self.path=='/register':
     e=str(d.get('email','')).strip().lower()
     if not re.fullmatch(r'[a-z0-9_]{3,24}',u) or not 8<=len(p)<=128 or '@' not in e or len(e)>254: raise ValueError('Invalid username, email or password (8+ characters)')
     if u==os.environ.get('LOLPRO_OWNER','').strip().lower(): raise ValueError('Nome reservado. Contate o suporte.')
     salt=secrets.token_hex(16); db.execute('INSERT INTO accounts(username,email,salt,password) VALUES(?,?,?,?)',(u,e,salt,digest(p,salt)))
    elif self.path=='/login':
     row=db.execute('SELECT salt,password,character FROM accounts WHERE username=?',(u,)).fetchone()
     if not row or len(p)>128 or not hmac.compare_digest(digest(p,row[0]),row[1]): raise ValueError('Usuário ou senha incorretos. Confira os dados ou contate o suporte.')
     if db.execute('SELECT 1 FROM bans WHERE username=?',(u,)).fetchone(): raise ValueError('Conta banida')
     token=secrets.token_urlsafe(32); db.execute('INSERT INTO sessions VALUES(?,?,?)',(token,u,int(time.time())+86400)); return self.reply({'ok':True,'token':token,'character':row[2],'characters':[{'slot':i,'name':name,'class':cl,'gender':gender,'avatar':avatar} for i,name,cl,gender,avatar in db.execute("SELECT c.slot,c.name,COALESCE(p.class,'Guerreiro'),COALESCE(p.gender,'Masculino'),COALESCE(a.avatar,'whiteclown') FROM characters c LEFT JOIN class_profiles p ON c.username=p.username AND c.slot=p.slot LEFT JOIN avatar_profiles a ON c.username=a.username AND c.slot=a.slot WHERE c.username=? ORDER BY c.slot",(u,))]})
    elif self.path=='/admin':
     row=db.execute('SELECT username FROM sessions WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     if not row: raise ValueError('Invalid session')
     uid=row[0]
     perms=admin_permissions(db,uid)
     cmd=str(d.get('command','')).strip()[:200]
     if not cmd: return self.reply({'ok':True,'permissions':perms})
     parts=cmd.lstrip('/').split()
     op=parts[0].lower()
     if op not in perms: raise ValueError('Sem permissão')
     if op in ('adm','removeradm','ban','desban'):
      if len(parts)<2: raise ValueError('Informe o usuário')
      target=parts[1].lower()
      if not db.execute('SELECT 1 FROM accounts WHERE username=?',(target,)).fetchone(): raise ValueError('Usuário inexistente')
      if target==os.environ.get('LOLPRO_OWNER','').strip().lower(): raise ValueError('Conta protegida')
      if op=='adm':
       allowed={'curar','nivel','dinheiro','ban','desban'}
       grants=parts[2:]
       if not set(grants)<=allowed: raise ValueError('Permissão inválida')
       db.execute('INSERT OR REPLACE INTO admins VALUES(?,?)',(target,json.dumps(grants)))
      elif op=='removeradm': db.execute('DELETE FROM admins WHERE username=?',(target,))
      elif op=='ban':
       db.execute('INSERT OR IGNORE INTO bans VALUES(?)',(target,))
       db.execute('DELETE FROM sessions WHERE username=?',(target,))
       with world_lock: players.pop(target,None)
      else: db.execute('DELETE FROM bans WHERE username=?',(target,))
     else:
      chosen=db.execute('SELECT slot FROM session_slots WHERE token=?',(str(d.get('token','')),)).fetchone()
      if not chosen: raise ValueError('Selecione personagem')
      slot=chosen[0]
      with world_lock:
       me=players.get(uid)
       if op=='curar':
        if not me or me['hp']<=0: raise ValueError('Personagem indisponível')
        me['hp']=me.get('max_hp',100); me['mana']=100
       else:
        if len(parts)!=2: raise ValueError('Informe um valor')
        value=int(parts[1])
        if op=='nivel' and 1<=value<=99: db.execute('UPDATE progress SET level=?,xp=0 WHERE username=? AND slot=?',(value,uid,slot))
        elif op=='dinheiro' and 0<value<=1000000: db.execute('UPDATE progress SET coins=coins+? WHERE username=? AND slot=?',(value,uid,slot))
        else: raise ValueError('Valor inválido')
     db.execute('INSERT INTO admin_audit VALUES(?,?,?)',(uid,cmd,int(time.time())))
     db.commit()
     return self.reply({'ok':True,'message':'Comando executado'})
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
     if not row: raise ValueError('Invalid session or character')
     chosen=db.execute('SELECT slot FROM session_slots WHERE token=?',(str(d.get('token','')),)).fetchone()
     slot=chosen[0] if chosen else 0
     char=db.execute('SELECT name FROM characters WHERE username=? AND slot=?',(row[0],slot)).fetchone()
     if not char: raise ValueError('Select character')
     row=(row[0],char[0])
     pos=d.get('pos')
     angle=d.get('angle')
     state=d.get('state')
     map_id=str(d.get('map_id','valoria'))
     if map_id not in ('valoria','bosses'): raise ValueError('Invalid map')
     if not isinstance(pos,list) or len(pos)!=3 or not all(type(v) in (int,float) and math.isfinite(v) and abs(v)<=150 for v in pos) or type(angle) not in (int,float) or not math.isfinite(angle) or state not in ('Idle','Walking','Running','Jumping'): raise ValueError('Invalid movement')
     # Shared presence is stored in the account database so clients served by
     # different web workers still see the same online world.
     now=time.time()
     with world_lock:
      db.execute('DELETE FROM world_presence WHERE seen<?',(now-15,))
      players.clear()
      for presence_user,payload,seen_at in db.execute('SELECT username,payload,seen FROM world_presence WHERE seen>?',(now-15,)).fetchall():
       try:
        presence=json.loads(payload)
        presence['seen']=float(seen_at)
        players[presence_user]=presence
       except (ValueError,TypeError):
        continue
      db.execute('INSERT OR IGNORE INTO progress(username,slot) VALUES(?,?)',(row[0],slot))
      saved=db.execute('SELECT level,xp,coins,potions,weapon,armor FROM progress WHERE username=? AND slot=?',(row[0],slot)).fetchone()
      if row[0] in players and players[row[0]].get('slot')!=slot: del players[row[0]]
      me=players.setdefault(row[0],{'id':row[0],'hp':100,'last_attack':-100,'attack_seq':'','respawn_at':0,'generation':0,'potions':5,'potion_seq':''})
      me.update(slot=slot,level=saved[0],xp=saved[1],coins=saved[2],potions=saved[3],weapon=saved[4],armor=saved[5])
      kinds=('helmet','boots','gloves','necklace','ring','bracelet','shield')
      gear={k:0 for k in kinds}
      gear.update(dict(db.execute('SELECT kind,equipped FROM gear WHERE username=? AND slot=?',(row[0],slot))))
      db.execute('INSERT OR IGNORE INTO pets(username,slot) VALUES(?,?)',(row[0],slot))
      pet=list(db.execute('SELECT level,xp,mission,summoned FROM pets WHERE username=? AND slot=?',(row[0],slot)).fetchone())
      me['gear']=gear
      profile=db.execute('SELECT class,gender FROM class_profiles WHERE username=? AND slot=?',(row[0],slot)).fetchone() or ('Guerreiro','Masculino')
      me['class'],me['gender']=profile
      avatar_row=db.execute('SELECT avatar FROM avatar_profiles WHERE username=? AND slot=?',(row[0],slot)).fetchone()
      me['avatar']=avatar_row[0] if avatar_row else 'whiteclown'
      ranks=dict(db.execute('SELECT kind,rank FROM upgrades WHERE username=? AND slot=?',(row[0],slot)))
      me['ranks']=ranks
      item=str(d.get('item',''))[:80]
      if item and item!=me.get('item_seq',''):
       me['item_seq']=item
       cmd=d.get('item_action')
       if cmd=='buy_potion' and me['coins']>=10: me['coins']-=10; me['potions']+=1
       elif cmd=='sell_potion' and me['potions']>0: me['coins']+=5; me['potions']-=1
       elif cmd=='pet_toggle': pet[3]=1-pet[3]
       elif cmd=='weapon': me['weapon']=1-me['weapon']
       elif cmd=='armor': me['armor']=1-me['armor']
       elif isinstance(cmd,str) and cmd.startswith('upgrade:'):
        kind=cmd.split(':',1)[1]
        rank=max(1,ranks.get(kind,1))
        cost=25*(rank+1)
        if kind in (*kinds,'weapon','armor') and rank<9 and me['coins']>=cost:
         me['coins']-=cost
         ranks[kind]=rank+1
         db.execute('INSERT OR REPLACE INTO upgrades VALUES(?,?,?,?)',(row[0],slot,kind,rank+1))
       elif cmd in kinds:
        gear[cmd]=1-gear[cmd]
        db.execute('INSERT OR REPLACE INTO gear VALUES(?,?,?,?)',(row[0],slot,cmd,gear[cmd]))
      if me['hp']==0 and now>=me['respawn_at']:
       me['hp']=me.get('max_hp',100); me['generation']+=1
      if d.get('generation',0)!=me['generation']: pos=[0,0.1,0]
      if pet[3] and pet[0]<99 and me['hp']>0:
       goal=([20,0,20],[-20,0,20],[-20,0,-20],[20,0,-20])[pet[2]%4]
       if math.hypot(pos[0]-goal[0],pos[2]-goal[2])<3:
        pet[2]+=1
        pet[1]+=100
        while pet[0]<99 and pet[1]>=100+(pet[0]-1)*50:
         pet[1]-=100+(pet[0]-1)*50
         pet[0]+=1
        if pet[0]==99: pet[1]=0
      db.execute('UPDATE pets SET level=?,xp=?,mission=?,summoned=? WHERE username=? AND slot=?',(*pet,row[0],slot))
      me['pet']={'level':pet[0],'xp':pet[1],'mission':pet[2],'summoned':bool(pet[3]),'goal':([20,20],[-20,20],[-20,-20],[20,-20])[pet[2]%4]}
      pa,pd,ph=pet_bonuses(me['pet'])
      old_max=me.get('max_hp',100)
      me['max_hp']=100+ph
      if me['hp']>0: me['hp']=max(1,min(me['max_hp'],me['hp']+me['max_hp']-old_max))
      me['pet'].update(attack=pa,defense=pd,life=ph)
      me.update(name=row[1],pos=pos,angle=angle,state=state,seen=now,map_id=map_id,free_combat=d.get('free_combat') is True)
      seq=str(d.get('attack',''))[:80]
      if seq and seq!=me['attack_seq']:
       me['attack_seq']=seq
       target_id=str(d.get('target_id',''))[:64]
       if me['hp']>0 and me.get('free_combat',False) and now-me['last_attack']>=0.6:
        me['last_attack']=now
        for key,target in players.items():
         if key==row[0] or target['hp']<=0 or target.get('map_id','valoria')!=map_id: continue
         if target_id and key!=target_id: continue
         dx,dy,dz=[target['pos'][i]-pos[i] for i in range(3)]
         dist=math.sqrt(dx*dx+dy*dy+dz*dz)
         in_range=dist<=3.0 if target_id else dist<=2.0
         facing=(dx*math.sin(angle)+dz*math.cos(angle))/max(dist,0.001)
         if 0.01<dist and in_range and (bool(target_id) or facing>0.3):
          damage=max(1,10+pa-pet_bonuses(target.get('pet',{}))[1]+(5+max(1,ranks.get('weapon',1))-1)*me['weapon']-(3+max(1,target.get('ranks',{}).get('armor',1))-1)*target.get('armor',0))
          target['hp']=max(0,target['hp']-damage)
          if target['hp']==0:
           target['respawn_at']=now+3
           me['xp']+=20; me['coins']+=5
           while me['level']<99 and me['xp']>=100+(me['level']-1)*50:
            me['xp']-=100+(me['level']-1)*50; me['level']+=1
           if me['level']>=99: me['xp']=0
      me.setdefault('mana',100.0)
      me['mana']=min(100.0,me['mana']+max(0,now-me.get('mana_time',now))*4)
      me['mana_time']=now
      cooldowns=me.setdefault('cooldowns',{})
      skill=str(d.get('skill_seq',''))[:80]
      idx=d.get('skill_index',-1)
      if skill and skill!=me.get('skill_ack',''):
       me['skill_ack']=skill
       if type(idx) is int and 0<=idx<6 and me['level']>=[5,8,10,12,15,20][idx] and me['hp']>0 and me['mana']>=10+idx*3 and now>=cooldowns.get(idx,0):
        me['mana']-=10+idx*3
        cooldowns[idx]=now+4+idx*2
        me['skill_event']=skill
        me['skill_index']=idx
        if profile[0]=='Xamã' and idx==0:
         me['hp']=min(me.get('max_hp',100),me['hp']+30)
        else:
         for key,target in players.items():
          if me.get('free_combat',False) and key!=row[0] and target.get('map_id','valoria')==map_id and target['hp']>0 and math.dist(pos,target['pos'])<= (5 if profile[0] in ('Xamã','Ninja') else 3):
           target['hp']=max(0,target['hp']-max(1,15+idx*4+pa-pet_bonuses(target.get('pet',{}))[1]))
           if target['hp']==0: target['respawn_at']=now+3
      potion=str(d.get('potion',''))[:80]
      if potion and potion!=me['potion_seq']:
       me['potion_seq']=potion
       if 0<me['hp']<me.get('max_hp',100) and me['potions']>0:
        me['potions']-=1; me['hp']=min(me.get('max_hp',100),me['hp']+20)
      others=[{k:item[k] for k in ('id','name','pos','angle','state','hp','attack_seq','weapon','armor','gear','ranks')} for key,item in players.items() if key!=row[0] and item.get('map_id','valoria')==map_id]
      for item in others:
       source=players[item['id']]
       item['pet']=source.get('pet',{})
       item['avatar']=source.get('avatar','whiteclown')
       item.update(class_name=source.get('class','Guerreiro'),skill_event=source.get('skill_event',''),skill_index=source.get('skill_index',-1))
      updated=tuple(me[k] for k in ('level','xp','coins','potions','weapon','armor'))
      if updated!=saved: db.execute('UPDATE progress SET level=?,xp=?,coins=?,potions=?,weapon=?,armor=? WHERE username=? AND slot=?',(*updated,row[0],slot))
      own={k:me[k] for k in ('hp','generation','potions','attack_seq','potion_seq','level','xp','coins','weapon','armor')}
      own['class'],own['gender']=profile
      own.update(mana=int(me['mana']),skill_ack=me.get('skill_ack',''),skill_event=me.get('skill_event',''),skill_index=me.get('skill_index',-1),cooldowns=[max(0,cooldowns.get(i,0)-now) for i in range(6)])
      own['max_hp']=me['max_hp']
      own['pet']=me['pet']
      own['gear']=gear
      own['ranks']=ranks
      own['item_seq']=me.get('item_seq','')
      if me['hp']>0:
       db.execute('INSERT OR REPLACE INTO character_positions VALUES(?,?,?,?,?,?)',(row[0],slot,*pos,angle))
      # Publish every currently visible player to the shared database. This
      # keeps the same map population visible across app workers/instances.
      for presence_user,presence in players.items():
       db.execute('INSERT INTO world_presence(username,slot,payload,seen) VALUES(?,?,?,?) ON CONFLICT(username) DO UPDATE SET slot=excluded.slot,payload=excluded.payload,seen=excluded.seen',
        (presence_user,int(presence.get('slot',0)),json.dumps(presence,separators=(',',':')),float(presence.get('seen',now))))
      db.execute('DELETE FROM world_presence WHERE seen<?',(now-15,))
      db.commit()
     return self.reply({'ok':True,'players':others,'self':own})
    elif self.path=='/delete_character':
     row=db.execute('SELECT username FROM sessions WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     if not row: raise ValueError('Sessão inválida. Entre novamente.')
     if not hmac.compare_digest(str(d.get('delete_password','')), '1234567'): raise ValueError('Senha de exclusão incorreta.')
     uid=row[0]
     slot=d.get('slot',-1)
     if type(slot) is not int or not 0<=slot<4: raise ValueError('Personagem inválido.')
     char=db.execute('SELECT name FROM characters WHERE username=? AND slot=?',(uid,slot)).fetchone()
     if not char: raise ValueError('Não existe personagem nesse espaço.')
     for table in ('characters','progress','character_positions','gear','upgrades','class_profiles','avatar_profiles','pets'):
      db.execute('DELETE FROM '+table+' WHERE username=? AND slot=?',(uid,slot))
     db.execute('DELETE FROM session_slots WHERE token=?',(str(d.get('token','')),))
     remaining=db.execute("SELECT name FROM characters WHERE username=? ORDER BY slot LIMIT 1",(uid,)).fetchone()
     db.execute('UPDATE accounts SET character=? WHERE username=?',((remaining[0] if remaining else ''),uid))
     db.commit()
     chars=[{'slot':i,'name':name,'class':cl,'gender':gender,'avatar':avatar} for i,name,cl,gender,avatar in db.execute("SELECT c.slot,c.name,COALESCE(p.class,'Guerreiro'),COALESCE(p.gender,'Masculino'),COALESCE(a.avatar,'whiteclown') FROM characters c LEFT JOIN class_profiles p ON c.username=p.username AND c.slot=p.slot LEFT JOIN avatar_profiles a ON c.username=a.username AND c.slot=a.slot WHERE c.username=? ORDER BY c.slot",(uid,))]
     return self.reply({'ok':True,'message':'Personagem excluído.','characters':chars,'character':remaining[0] if remaining else ''})
    elif self.path=='/character':
     row=db.execute('SELECT username FROM sessions WHERE token=? AND expires>?',(str(d.get('token','')),int(time.time()))).fetchone()
     name=str(d.get('character','')).strip()
     if not row or not 3<=len(name)<=24 or not all(c.isalnum() or c in '_ ' for c in name): raise ValueError('Invalid session or character name')
     slot=d.get('slot',0)
     if type(slot) is not int or not 0<=slot<4: raise ValueError('Invalid slot')
     existing=db.execute('SELECT name FROM characters WHERE username=? AND slot=?',(row[0],slot)).fetchone()
     if existing and existing[0]!=name: raise ValueError('Slot already occupied')
     cl='Aventureiro'; gender=d.get('gender','Masculino')
     if gender != 'Masculino': raise ValueError('Apenas personagens masculinos estão disponíveis.')
     db.execute('INSERT OR IGNORE INTO characters VALUES(?,?,?)',(row[0],slot,name))
     db.execute('INSERT OR IGNORE INTO class_profiles VALUES(?,?,?,?)',(row[0],slot,cl,gender))
     avatar=str(d.get('avatar','whiteclown'))
     if avatar not in ('whiteclown','sura','warrior_m'): raise ValueError('Personagem indisponível.')
     db.execute('INSERT OR REPLACE INTO avatar_profiles VALUES(?,?,?)',(row[0],slot,avatar))
     db.execute('UPDATE accounts SET character=? WHERE username=?',(name,row[0]))
     db.execute('INSERT OR REPLACE INTO session_slots VALUES(?,?)',(str(d.get('token','')),slot))
     location=db.execute('SELECT x,y,z,angle FROM character_positions WHERE username=? AND slot=?',(row[0],slot)).fetchone()
     db.commit()
     return self.reply({'ok':True,'position':list(location[:3]) if location else [0,0.65,0],'angle':location[3] if location else 0})
    else: raise ValueError('Unknown endpoint')
   self.reply({'ok':True})
  except integrity_errors: self.reply({'ok':False,'error':'Account already exists'})
  except database_errors as exc:
   print('Database error:',type(exc).__name__,str(exc),flush=True)
   self.reply({'ok':False,'error':'Banco de dados indisponível'})
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
