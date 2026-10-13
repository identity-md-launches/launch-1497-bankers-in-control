/** Browser validation against the production export. Wallets and RPCs in fixture tests are synthetic.
 * No keys, real accounts, signatures or broadcasts are used. --live enables read-only RPC smoke.
 * Screenshots/results go outside the repository unless --out explicitly selects artifacts/.
 */
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { dirname, extname, resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium, webkit } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { decodeFunctionData, encodeFunctionResult, encodeEventTopics, encodeAbiParameters, keccak256, stringToHex, toHex, zeroAddress } from 'viem';
const here = dirname(fileURLToPath(import.meta.url));
const arg = name => { const i = process.argv.indexOf(name); return i < 0 ? null : process.argv[i + 1]; };
const dist = resolve(arg('--dist') || join(here, '../../dist'));
const out = resolve(arg('--out') || '/tmp/bic-validation');
await mkdir(out, { recursive: true });
const deployment = JSON.parse(await readFile(join(here, '../src/contracts/deployment.json'), 'utf8'));
const codes = JSON.parse(await readFile(join(here, 'fixtures/runtime.json'), 'utf8'));
const readAbi = async name => JSON.parse((await readFile(join(here, `../src/contracts/${name}.ts`), 'utf8')).split(' = ')[1].split(' as const;')[0]);
const claimAbi = await readAbi('CharterClaim'), tokenAbi = await readAbi('LaunchToken');
const charterAbi = [
 {type:'function',name:'ownerOf',stateMutability:'view',inputs:[{name:'id',type:'uint256'}],outputs:[{type:'address'}]},
 {type:'function',name:'balanceOf',stateMutability:'view',inputs:[{name:'account',type:'address'}],outputs:[{type:'uint256'}]},
];
const A = '0x1111111111111111111111111111111111111111';
const B = '0x2222222222222222222222222222222222222222';
const txHash = keccak256(stringToHex('BIC browser test transaction: never broadcast'));
const blockHash = keccak256(stringToHex('BIC browser test block'));
const server = createServer(async (req, res) => {
  const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  if (!pathname.startsWith('/preview/')) { res.writeHead(404); res.end(); return; }
  const relative = pathname.slice('/preview/'.length) || 'index.html';
  const file = resolve(dist, relative);
  if (!file.startsWith(dist + '/')) { res.writeHead(403); res.end(); return; }
  try {
    const data = await readFile(file);
    res.setHeader('Content-Type', ({ '.html':'text/html', '.css':'text/css', '.js':'text/javascript', '.svg':'image/svg+xml', '.png':'image/png', '.woff2':'font/woff2' })[extname(file)] || 'application/octet-stream');
    res.end(data);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/preview/`;
const report = { checkedAt: new Date().toISOString(), export: dist, tests: [], screenshots: [], limitations: [] };
let browser;
const browsers = [];
async function test(name, fn) {
  if (arg('--filter') && !name.includes(arg('--filter'))) return;
  try { await fn(); report.tests.push({ name, passed: true }); console.log('PASS', name); }
  catch (e) { report.tests.push({ name, passed: false, error: e.stack }); console.error('FAIL', name, e.message); }
}
async function shot(page, name, fullPage = false) {
  await page.screenshot({ path: join(out, name + '.png'), fullPage }); report.screenshots.push(name + '.png');
}
async function rpcMock(route, state) {
  if (state.offline) { await route.abort('failed'); return; }
  const payload = route.request().postDataJSON();
  const handle = call => {
    const { id, method, params = [] } = call;
    const ok = result => ({ jsonrpc: '2.0', id, result });
    const fail = (message, code = -32000) => ({ jsonrpc: '2.0', id, error: { code, message, data: '0x' } });
    if (method === 'eth_chainId') return ok(state.rpcWrongChain ? '0x1' : toHex(deployment.chainId));
    if (method === 'eth_blockNumber') return ok(toHex(87218580 + (state.mined ? 1 : 0)));
    if (method === 'eth_getCode') return ok(state.badCode ? '0x6000' : codes[params[0].toLowerCase()] || '0x');
    if (method === 'eth_getTransactionReceipt') {
      if (!state.mined) return ok(null);
      const id = BigInt(state.receiptId || 42);
      const stage = state.sentStage || 'instant';
      const value = BigInt(deployment.constants[stage === 'instant' ? 'INSTANT' : 'REST']);
      const failed = Boolean(state.reverted);
      if (!failed) { state.recorded = 'account'; if (stage === 'rest') state.paid = true; }
      return ok({ transactionHash: txHash, transactionIndex: '0x0', blockHash, blockNumber: toHex(87218581), from: A, to: deployment.claim, cumulativeGasUsed:'0x10000',gasUsed:'0x10000',contractAddress:null,status:failed?'0x0':'0x1',effectiveGasPrice:'0x1',type:'0x2',logsBloom:'0x'+'0'.repeat(512),logs:failed?[]:[{ address:deployment.claim,topics:encodeEventTopics({abi:claimAbi,eventName:'Claimed',args:{id,account:A}}),data:encodeAbiParameters([{type:'uint256'},{type:'bool'}],[value,stage==='rest']),blockNumber:toHex(87218581),transactionHash:txHash,transactionIndex:'0x0',blockHash,logIndex:'0x0',removed:false }] });
    }
    if (method === 'eth_getBlockByNumber') return ok({number:toHex(87218580+(state.mined?1:0)),hash:blockHash,parentHash:blockHash,nonce:'0x0000000000000000',sha3Uncles:blockHash,logsBloom:'0x'+'0'.repeat(512),transactionsRoot:blockHash,stateRoot:blockHash,receiptsRoot:blockHash,miner:A,difficulty:'0x0',totalDifficulty:'0x0',extraData:'0x',size:'0x100',gasLimit:'0x1000000',gasUsed:'0x10000',timestamp:toHex(1791864000),transactions:[],uncles:[],baseFeePerGas:'0x1'});
    if (method === 'eth_getTransactionByHash') return ok({hash:txHash,from:A,to:deployment.claim,nonce:'0x0',gas:'0x10000',value:'0x0',input:'0x',v:'0x1',r:'0x1',s:'0x1',type:'0x2',chainId:toHex(deployment.chainId),maxFeePerGas:'0x1',maxPriorityFeePerGas:'0x1',blockNumber:state.mined?toHex(87218581):null,blockHash:state.mined?blockHash:null,transactionIndex:state.mined?'0x0':null});
    if (method === 'eth_call') {
      const callData = params[0], address = callData.to.toLowerCase();
      const abi = address === deployment.claim ? claimAbi : address === deployment.token ? tokenAbi : charterAbi;
      const { functionName, args } = decodeFunctionData({ abi, data: callData.data });
      state.calls.push({ functionName, args: args?.map(String) });
      let result;
      if (functionName === 'token') result = deployment.token;
      else if (functionName === 'CHARTER') result = deployment.constants.CHARTER;
      else if (functionName === 'claimant') result = state.recorded === 'account' ? A : state.recorded === 'other' ? B : zeroAddress;
      else if (functionName === 'restClaimed') result = Boolean(state.paid);
      else if (functionName === 'ownerOf') { if (state.missing) return fail('execution reverted: nonexistent token'); result = state.owner === 'other' ? B : A; }
      else if (functionName === 'balanceOf') result = address === deployment.token ? state.underfunded ? 1n : BigInt(deployment.constants.ALLOCATION) : BigInt(state.charterBalance ?? 1);
      else if (functionName === 'claim' || functionName === 'claimRest') { state.sentStage = functionName === 'claim' ? 'instant' : 'rest'; if (state.simulationRevert) return fail('execution reverted: eligibility changed'); return ok('0x'); }
      else throw new Error(`Unexpected call ${functionName}`);
      return ok(encodeFunctionResult({ abi, functionName, result }));
    }
    console.error(`Unexpected RPC method ${method}`); return fail(`Unexpected RPC method ${method}`);
  };
  if (state.delay) await new Promise(r => setTimeout(r, state.delay));
  await route.fulfill({ json: Array.isArray(payload) ? payload.map(handle) : handle(payload), headers: { 'access-control-allow-origin': '*' } });
}
async function fixture(options = {}, engine = browser) {
  const context = await engine.newContext({ viewport: { width: 390, height: 844 } });
  const state = { calls: [], charterBalance:1, ...options };
  await context.route('https://**/*', route => rpcMock(route, state));
  if (!options.noWallet) await context.addInitScript(({ A, B, txHash, chainId, opts }) => {
    const listeners = {};
    const wallet = {
      account: A, chainId: opts.wrongChain ? '0x1' : '0x' + chainId.toString(16), sent: [], switches:0, added:0,
      rejectConnect:Boolean(opts.rejectConnect), rejectSend:Boolean(opts.rejectSend), unknownChain:Boolean(opts.unknownChain),
      emit(name, value) { for (const fn of listeners[name] || []) fn(value); },
      setAccount(other) { this.account = other ? B : A; this.emit('accountsChanged', [this.account]); },
      async request({ method, params }) {
        if (method === 'eth_accounts') return [this.account];
        if (method === 'eth_requestAccounts') { if (this.rejectConnect) throw Object.assign(new Error('User rejected connection'), { code:4001 }); return [this.account]; }
        if (method === 'eth_chainId') return this.chainId;
        if (method === 'wallet_switchEthereumChain') { this.switches++; if (this.unknownChain) throw Object.assign(new Error('Unrecognized chain'), { code:4902 }); this.chainId=params[0].chainId; this.emit('chainChanged', this.chainId); return null; }
        if (method === 'wallet_addEthereumChain') { this.added++; this.unknownChain=false; return null; }
        if (method === 'eth_sendTransaction') { if (this.rejectSend) throw Object.assign(new Error('User rejected transaction'), { code:4001 }); this.sent.push(params[0]); return txHash; }
        throw Error('Unexpected wallet request: ' + method);
      },
      on(event, handler) { (listeners[event] ||= []).push(handler); },
      removeListener(event, handler) { listeners[event] = (listeners[event] || []).filter(fn => fn !== handler); },
    };
    window.ethereum = wallet; window.__testWallet = wallet;
  }, { A, B, txHash, chainId:deployment.chainId, opts:options });
  const page = await context.newPage();
  page.setDefaultTimeout(8000);
  const errors = [], missing = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('response', res => { if (res.url().startsWith(url) && res.status() >= 400) missing.push(res.url()); });
  await page.goto(url);
  await page.evaluate(() => document.fonts.ready);
  if (!state.badCode && !state.offline && !state.rpcWrongChain) await page.getByText('Robinhood Chain · Contracts verified', { exact:true }).waitFor();
  return { page, context, state, errors, missing };
}
async function connect(page) {
  await page.locator('.connect-main').click();
  await page.getByRole('button', {name:'Browser wallet',exact:true}).click();
  await page.getByRole('button',{name:'Manage wallet',exact:true}).waitFor();
}
async function lookup(page, id='42') {
  await page.getByLabel('Charter ID',{exact:true}).fill(id);
  await page.getByRole('button',{name:'Check ID',exact:true}).click();
}
try {
  browser = await chromium.launch({ headless: true, args:['--no-sandbox'] }); browsers.push(browser);
  await test('Static subpath, mobile first action, responsive layouts and local fonts', async () => {
    const {page,context,errors,missing}=await fixture({noWallet:true});
    for (const [width,height] of [[320,812],[390,844],[768,1024],[1440,1000]]) {
      await page.setViewportSize({width,height});
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,`overflow at ${width}`);
      if (width===390) { const box=await page.locator('.connect-main').boundingBox(); assert(box.y+box.height<height); await shot(page,'mobile-first-screen'); }
      if (width===1440) { await shot(page,'desktop-first-screen'); await shot(page,'desktop-full',true); }
    }
    assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);
    assert(await page.evaluate(()=>[...document.fonts].every(f=>f.status==='loaded')));
    await context.close();
  });
  await test('No-wallet guidance, native dialog keyboard trap, Escape and focus return',async()=>{
    const {page,context}=await fixture({noWallet:true});
    await page.locator('.connect-main').focus(); await page.keyboard.press('Enter');
    await page.getByText('No browser wallet found.',{exact:true}).waitFor();
    for(let i=0;i<6;i++){await page.keyboard.press('Tab');assert(await page.evaluate(()=>document.activeElement === document.body || Boolean(document.activeElement.closest('dialog'))));}
    await shot(page,'wallet-guidance');await page.keyboard.press('Escape');
    assert(await page.locator('.connect-main').evaluate(el=>el===document.activeElement));
    await shot(page,'keyboard-focus');await context.close();
  });
  await test('ID validation: empty, zero, above maximum, decimals and valid upper boundary',async()=>{
    const {page,context,state}=await fixture({noWallet:true});
    await page.getByRole('button',{name:'Check a Charter ID'}).click();
    for(const id of ['', '0','1033','2.5']) {await lookup(page,id);await page.locator('#id-error').waitFor();assert.equal(await page.locator('#charter-id').getAttribute('aria-invalid'),'true');}
    await lookup(page,'1032');await page.getByText('The first 10% is unclaimed.',{exact:true}).waitFor();
    assert(state.calls.some(c=>c.functionName==='claimant'&&c.args[0]==='1032'));await context.close();
  });
  await test('FAQ disclosures, anchor navigation, clipboard and reduced motion',async()=>{
    const {page,context}=await fixture({noWallet:true});
    await page.getByText('Do I have to burn my Charter?',{exact:true}).click();assert(await page.locator('details').filter({hasText:'Do I have to burn my Charter?'}).getAttribute('open')!==null);
    await page.getByRole('link',{name:'Back to your claim'}).click();assert.equal(new URL(page.url()).hash,'#claim');
    await context.grantPermissions(['clipboard-read','clipboard-write']);await page.getByRole('button',{name:'Copy address'}).click();
    assert.equal(await page.evaluate(()=>navigator.clipboard.readText()),deployment.token);
    await page.emulateMedia({reducedMotion:'reduce'});assert.equal(await page.locator('.connect-main').evaluate(el=>getComputedStyle(el).transitionDuration),'0s');
    await context.close();
  });
  await test('Wallet connection rejection recovers without claiming connection',async()=>{
    const {page,context}=await fixture({rejectConnect:true});await page.locator('.connect-main').click();await page.getByRole('button',{name:'Browser wallet',exact:true}).click();
    await page.getByText('Request declined in your wallet. You can try again when ready.',{exact:true}).waitFor();
    await page.evaluate(()=>{window.__testWallet.rejectConnect=false;});await page.getByRole('button',{name:'Browser wallet',exact:true}).click();await page.getByRole('button',{name:'Manage wallet',exact:true}).waitFor();await context.close();
  });
  await test('Wrong network, add-chain fallback and switching',async()=>{
    const {page,context}=await fixture({wrongChain:true,unknownChain:true});await connect(page);await shot(page,'wrong-network');
    await page.getByRole('button',{name:'Switch network',exact:true}).click();await page.getByText('Switch to Robinhood Chain to claim BIC.',{exact:true}).waitFor({state:'hidden'});
    assert.deepEqual(await page.evaluate(()=>[window.__testWallet.chainId,window.__testWallet.switches,window.__testWallet.added]),[toHex(deployment.chainId),2,1]);await context.close();
  });
  for(const [name,options,expected] of [
    ['Wrong Charter owner',{owner:'other'},'This wallet does not own this Charter.'],
    ['Already claimed ID',{recorded:'other'},'The first 10% was already claimed.'],
    ['Burned or unminted ID',{missing:true},'This Charter has no current owner.'],
  ]) await test(name,async()=>{const {page,context}=await fixture(options);await connect(page);await lookup(page);await page.getByText(expected,{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'Review claim',exact:true}).count(),0);await context.close();});
  await test('10% review and wallet rejection, no approval requested',async()=>{
    const {page,context}=await fixture({rejectSend:true});await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).click();await page.getByRole('heading',{name:'Review your claim'}).waitFor();await shot(page,'claim-review');
    await page.getByRole('button',{name:'Confirm in wallet'}).click();await page.getByText('Request declined in your wallet. You can try again when ready.',{exact:true}).waitFor();assert.equal(await page.evaluate(()=>window.__testWallet.sent.length),0);await context.close();
  });
  await test('10% transaction calldata, pending state and receipt-confirmed success',async()=>{
    const {page,context,state}=await fixture();await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).click();await page.getByRole('button',{name:'Confirm in wallet'}).click();
    await page.getByText('Transaction submitted.',{exact:true}).waitFor();await shot(page,'claim-pending');
    const sent=await page.evaluate(()=>window.__testWallet.sent);assert.equal(sent.length,1);assert.equal(sent[0].to.toLowerCase(),deployment.claim);assert.deepEqual(decodeFunctionData({abi:claimAbi,data:sent[0].data}),{functionName:'claim',args:[[42n]]});
    state.mined=true;await page.getByText('Claim confirmed. Welcome to the takeover.',{exact:true}).waitFor({timeout:15000});await shot(page,'claim-success');await context.close();
  });
  for(const [name,options,expected] of [
    ['90% before first claim',{},'Claim the first 10% first.'],
    ['90% wrong claimant',{recorded:'other'},'Use the original claimant wallet.'],
    ['90% holds any Charter',{recorded:'account',charterBalance:2},'The golden handcuffs are still on.'],
    ['90% already paid',{recorded:'account',paid:true,charterBalance:0},'This Charter is fully paid.'],
  ]) await test(name,async()=>{const {page,context}=await fixture(options);await connect(page);await page.getByRole('button',{name:'Release 90%',exact:true}).click();await lookup(page);await page.getByText(expected,{exact:true}).waitFor();if(options.charterBalance===2)await shot(page,'rest-locked');assert.equal(await page.getByRole('button',{name:'Review release',exact:true}).count(),0);await context.close();});
  await test('90% zero-balance release uses claimRest and confirms expected payout',async()=>{
    const {page,context,state}=await fixture({recorded:'account',charterBalance:0});await connect(page);await page.getByRole('button',{name:'Release 90%',exact:true}).click();await lookup(page);await page.getByRole('button',{name:'Review release',exact:true}).click();await page.getByRole('button',{name:'Confirm in wallet'}).click();await page.getByText('Transaction submitted.',{exact:true}).waitFor();
    const sent=await page.evaluate(()=>window.__testWallet.sent);assert.deepEqual(decodeFunctionData({abi:claimAbi,data:sent[0].data}),{functionName:'claimRest',args:[[42n]]});state.mined=true;await page.getByText('Claim confirmed. Welcome to the takeover.',{exact:true}).waitFor({timeout:15000});await context.close();
  });
  await test('Account change invalidates a previous eligible result',async()=>{
    const {page,context}=await fixture();await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).waitFor();await page.evaluate(()=>window.__testWallet.setAccount(true));await page.getByRole('button',{name:'Review claim',exact:true}).waitFor({state:'hidden'});await lookup(page);await page.getByText('This wallet does not own this Charter.',{exact:true}).waitFor();await context.close();
  });
  await test('Eligibility is re-read before wallet submission',async()=>{
    const {page,context,state}=await fixture();await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).click();state.recorded='other';await page.getByRole('button',{name:'Confirm in wallet'}).click();await page.locator('.error-text').filter({hasText:'The first 10% was already claimed.'}).waitFor();assert.equal(await page.evaluate(()=>window.__testWallet.sent.length),0);await context.close();
  });
  await test('Underfunded reserve blocks wallet submission',async()=>{
    const {page,context}=await fixture({underfunded:true});await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).click();await page.getByRole('button',{name:'Confirm in wallet'}).click();await page.getByText(/does not have enough BIC/).waitFor();assert.equal(await page.evaluate(()=>window.__testWallet.sent.length),0);await context.close();
  });
  await test('Reverted receipt and unexpected claim log never show success',async()=>{
    for(const options of [{reverted:true},{receiptId:43}]) {
      const {page,context,state}=await fixture(options);await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).click();await page.getByRole('button',{name:'Confirm in wallet'}).click();await page.getByText('Transaction submitted.',{exact:true}).waitFor();state.mined=true;await page.getByText('Claim not completed.',{exact:true}).waitFor({timeout:15000});assert.equal(await page.getByText('Claim confirmed. Welcome to the takeover.',{exact:true}).count(),0);await context.close();
    }
  });
  await test('Network outage and deployment mismatch disable claims, retry recovers',async()=>{
    for(const options of [{offline:true},{badCode:true},{rpcWrongChain:true}]) {
      const {page,context,state}=await fixture(options);await page.getByRole('button',{name:'Retry connection'}).waitFor({timeout:20000});await page.getByRole('button',{name:'Check a Charter ID'}).click();assert(await page.getByRole('button',{name:'Check ID',exact:true}).isDisabled());if(options.offline)await shot(page,'rpc-unavailable');state.offline=false;state.badCode=false;state.rpcWrongChain=false;await page.getByRole('button',{name:'Retry connection'}).click();await page.getByText('Robinhood Chain · Contracts verified',{exact:true}).waitFor();assert.equal(await page.getByRole('button',{name:'Check ID',exact:true}).isDisabled(),false);await context.close();
    }
  });
  await test('Axe accessibility audit: initial, lookup error, wallet dialog, eligible and review',async()=>{
    const {page,context}=await fixture();
    const audit=async label=>{const result=await new AxeBuilder({page}).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze();await writeFile(join(out,`axe-${label}.json`),JSON.stringify(result.violations,null,2));assert.deepEqual(result.violations.map(v=>({id:v.id,nodes:v.nodes.map(n=>n.target)})),[],label);};
    await audit('initial');await page.getByRole('button',{name:'Check a Charter ID'}).click();await lookup(page,'0');await audit('invalid');await page.locator('.connect-main').click();await audit('wallet');await page.getByRole('button',{name:'Browser wallet',exact:true}).click();await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).waitFor();await audit('eligible');await page.getByRole('button',{name:'Review claim',exact:true}).click();await audit('review');await context.close();
  });
  await test('200% text enlargement preserves reflow and usable controls',async()=>{
    const {page,context}=await fixture({noWallet:true});await page.addStyleTag({content:'html{font-size:32px!important}'});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.locator('.connect-main').click();await page.getByText('No browser wallet found.',{exact:true}).waitFor();await shot(page,'text-enlargement');await context.close();
  });
  if(process.argv.includes('--live')) await test('Live read-only RPC verification and unconnected ID lookup',async()=>{
    const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();await page.goto(url);await page.getByText('Robinhood Chain · Contracts verified',{exact:true}).waitFor({timeout:40000});await page.getByRole('button',{name:'Check a Charter ID'}).click();await lookup(page,'1');await page.locator('.eligibility strong').waitFor({timeout:30000});report.liveObservation={chain:await page.locator('.chain-status').innerText(),result:await page.locator('.eligibility').innerText(),reserve:await page.locator('.contract-balance').innerText()};await shot(page,'live-read');await context.close();
  });
  if(process.argv.includes('--webkit')) {
    try { const wk=await webkit.launch({headless:true,timeout:12000});browsers.push(wk);await test('WebKit mobile connection, initial claim review and FAQ',async()=>{const {page,context,errors}=await fixture({},wk);await connect(page);await lookup(page);await page.getByRole('button',{name:'Review claim',exact:true}).click();await page.getByRole('heading',{name:'Review your claim'}).waitFor();await shot(page,'webkit-review');await page.keyboard.press('Escape');await page.getByText('Do I have to burn my Charter?',{exact:true}).click();assert.deepEqual(errors,[]);assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await context.close();}); }
    catch(e){report.limitations.push('WebKit could not launch: '+e.message);console.error('WEBKIT LIMITATION',e.message);}
  }
} finally {
  for(const instance of browsers) await instance.close();
  await new Promise(r=>server.close(r));
  await writeFile(join(out,'results.json'),JSON.stringify(report,null,2)+'\n');
}
const failures=report.tests.filter(t=>!t.passed);console.log(`${report.tests.length-failures.length}/${report.tests.length} checks passed`);
if(failures.length) process.exitCode=1;
