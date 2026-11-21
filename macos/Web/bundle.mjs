import {build} from 'esbuild';
import {resolve} from 'node:path';
const output=process.argv[2];
if(!output) throw Error('Expected output file');
await build({entryPoints:[new URL('pet.js',import.meta.url).pathname],outfile:resolve(output),
  bundle:true,format:'iife',target:'safari16',minify:true,legalComments:'inline',
  loader:{'.wav':'base64'},define:{'import.meta.url':'"file:///unused-in-native-bundle"'}});
