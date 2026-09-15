"""Create original loopable pentatonic ambience and soft magical combat sounds."""
from pathlib import Path
import wave
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'games/forma-playground/assets'
RATE=22050
rng=np.random.default_rng(90337)
def save(name,samples):
    data=np.int16(np.clip(samples,-1,1)*32767)
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(data.tobytes())
n=RATE*24;t=np.arange(n)/RATE
# Integer-cycle tones make the pad continuous at the loop boundary.
music=.032*np.sin(2*np.pi*110*t)+.022*np.sin(2*np.pi*165*t)+.012*np.sin(2*np.pi*220*t)
for i,note in enumerate([57,64,69,67,64,60,57,64,72,69,67,64,60,64,67,69]):
    f=440*2**((note-69)/12)
    u=np.arange(RATE*4)/RATE
    tone=(np.sin(2*np.pi*f*u)+.35*np.sin(2*np.pi*f*2.003*u)+.15*np.sin(2*np.pi*f*3*u))
    env=(1-np.exp(-u*130))*np.exp(-u*1.7)
    start=int(i*1.5*RATE)
    idx=(start+np.arange(len(u)))%n
    music[idx]+=.075*tone*env
    music[(idx+int(.375*RATE))%n]+=.021*tone*env
save('lantern_music',music)
u=np.arange(int(.28*RATE))/RATE
save('lantern_cast',.2*np.sin(2*np.pi*(820*u-650*u*u))*np.exp(-u*15)*(1-np.exp(-u*500)))
u=np.arange(int(.5*RATE))/RATE
noise=rng.normal(0,1,len(u));noise=np.convolve(noise,np.ones(7)/7,mode='same')
save('lantern_dash',.35*noise*np.sin(np.pi*u/.5)**2+.08*np.sin(2*np.pi*(160*u-110*u*u))*np.exp(-u*8))
u=np.arange(int(.22*RATE))/RATE
save('lantern_hit',(.17*rng.normal(0,1,len(u))+.3*np.sin(2*np.pi*(120*u-170*u*u)))*np.exp(-u*30))
print('Prepared four original Lanternfall audio files')
