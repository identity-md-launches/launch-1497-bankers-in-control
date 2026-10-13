/** Compare regenerated ABI + deployed runtime with the pinned deployment. Read-only RPC. */
import { readFile } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPublicClient, http, keccak256, stringToHex } from 'viem';
const source = resolve(dirname(fileURLToPath(import.meta.url)), '../src/contracts');
const deployment = JSON.parse(await readFile(join(source, 'deployment.json'), 'utf8'));
const network = JSON.parse(await readFile(join(source, 'network.json'), 'utf8'));
const artifacts = process.argv[2];
if (!artifacts) throw new Error('Supply the absolute directory produced by forge build --out.');
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const client = createPublicClient({ transport: http(network.network.rpcUrls[0], {timeout: 20000}) });
const chainId = await client.getChainId();
if (chainId !== deployment.chainId) throw new Error('Wrong chain ID.');
const report = { checkedAt:new Date().toISOString(), sourceCommit:deployment.sourceCommit, chainId, contracts:[] };
for (const pinned of deployment.contracts) {
  const artifact = JSON.parse(await readFile(join(artifacts,`${pinned.name}.sol`,`${pinned.name}.json`),'utf8'));
  const abiHash = keccak256(stringToHex(JSON.stringify(canonical(artifact.abi)))).slice(2);
  if (abiHash !== pinned.abiHash) throw new Error(`${pinned.name}: ABI hash mismatch.`);
  const code = await client.getCode({ address:pinned.address });
  let expected = artifact.deployedBytecode.object;
  if (pinned.name === 'CharterClaim') {
    const token = await client.readContract({address:pinned.address,abi:artifact.abi,functionName:'token'});
    if (token.toLowerCase() !== deployment.token.toLowerCase()) throw new Error('Immutable token mismatch.');
    for (const refs of Object.values(artifact.deployedBytecode.immutableReferences)) for (const {start,length} of refs) {
      expected = expected.slice(0,2+start*2)+token.slice(2).toLowerCase().padStart(length*2,'0')+expected.slice(2+(start+length)*2);
    }
    for(const [functionName, value] of Object.entries(deployment.constants)) {
      const actual = await client.readContract({address:pinned.address,abi:artifact.abi,functionName});
      if(String(actual).toLowerCase() !== value.toLowerCase()) throw new Error(`Constant ${functionName} mismatch.`);
    }
  }
  if (!code || code.toLowerCase() !== expected.toLowerCase() || keccak256(code) !== pinned.runtimeCodeHash) throw new Error(`${pinned.name}: runtime mismatch.`);
  report.contracts.push({name:pinned.name,address:pinned.address,abiHash,runtimeCodeHash:keccak256(code),matchesCompiledSource:true});
}
console.log(JSON.stringify(report,null,2));
