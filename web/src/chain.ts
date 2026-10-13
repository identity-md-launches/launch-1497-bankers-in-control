import {
  createPublicClient, createWalletClient, custom, defineChain, fallback, http,
  keccak256, formatUnits, isAddress, zeroAddress, decodeEventLog,
  type Address, type EIP1193Provider, type Hash, type Log,
} from 'viem';
import deployment from './contracts/deployment.json';
import network from './contracts/network.json';
import { claimAbi } from './contracts/CharterClaim';
import { tokenAbi } from './contracts/LaunchToken';

export { deployment, network };
export type Provider = EIP1193Provider;
export const tokenAddress = deployment.token as Address;
export const claimAddress = deployment.claim as Address;
export const charterAddress = deployment.constants.CHARTER as Address;
export const MAX_ID = Number(deployment.constants.MAX_ID);
export const SHARE = BigInt(deployment.constants.SHARE);
export const INSTANT = BigInt(deployment.constants.INSTANT);
export const REST = BigInt(deployment.constants.REST);
export const robinhood = defineChain({
  id: network.network.chainId, name: network.network.name,
  nativeCurrency: network.network.nativeCurrency,
  rpcUrls: { default: { http: network.network.rpcUrls } },
  blockExplorers: { default: { name: 'Robinhood Explorer', url: network.network.explorer } },
});
export const publicClient = createPublicClient({
  chain: robinhood,
  transport: fallback(network.network.rpcUrls.map(url => http(url, { timeout: 12_000, retryCount: 0 })), { retryCount: 0 }),
});
// This interface is derived directly from src/interfaces/IFoundingCharter.sol.
export const charterAbi = [
  { type: 'function', name: 'ownerOf', stateMutability: 'view', inputs: [{ name: 'id', type: 'uint256' }], outputs: [{ name: '', type: 'address' }] },
  { type: 'function', name: 'balanceOf', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
] as const;

export type Stage = 'instant' | 'rest';
export type Eligibility = { id: bigint; stage: Stage; account: Address | null; eligible: boolean; title: string; detail: string; amount: bigint; charterBalance?: bigint };
export type ChainState = { reserve: bigint; block: bigint };
export const sameAddress = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
export const shortAddress = (a: string) => `${a.slice(0, 6)}…${a.slice(-4)}`;
export const explorer = (kind: 'address' | 'tx', value: string) => `${network.network.explorer}/${kind}/${value}`;
export function amount(value: bigint, decimals = 2): string {
  const [whole, fraction = ''] = formatUnits(value, 18).split('.');
  return Number(whole).toLocaleString('en-US') + (decimals ? '.' + fraction.padEnd(decimals, '0').slice(0, decimals) : '');
}
export const exactAmount = (value: bigint) => formatUnits(value, 18);
export function parseId(input: string): bigint {
  if (!/^\d+$/.test(input.trim())) throw new Error(`Enter a whole Charter ID from 1 to ${MAX_ID.toLocaleString('en-US')}.`);
  const id = BigInt(input.trim());
  if (id < 1n || id > BigInt(MAX_ID)) throw new Error(`Only Charter IDs 1–${MAX_ID.toLocaleString('en-US')} are eligible.`);
  return id;
}

export async function verifyDeployment(): Promise<ChainState> {
  const chainId = await publicClient.getChainId();
  if (chainId !== robinhood.id) throw new Error('The RPC returned a different network. Claims are disabled.');
  const block = await publicClient.getBlockNumber({ cacheTime: 0 });
  const codes = await Promise.all(deployment.contracts.map(c => publicClient.getCode({ address: c.address as Address, blockNumber: block })));
  codes.forEach((code, i) => {
    if (!code || keccak256(code) !== deployment.contracts[i].runtimeCodeHash) throw new Error('Contract verification failed. Claims are disabled.');
  });
  const [liveToken, liveCharter, charterCode, reserve] = await Promise.all([
    publicClient.readContract({ address: claimAddress, abi: claimAbi, functionName: 'token', blockNumber: block }),
    publicClient.readContract({ address: claimAddress, abi: claimAbi, functionName: 'CHARTER', blockNumber: block }),
    publicClient.getCode({ address: charterAddress, blockNumber: block }),
    publicClient.readContract({ address: tokenAddress, abi: tokenAbi, functionName: 'balanceOf', args: [claimAddress], blockNumber: block }),
  ]);
  if (!sameAddress(liveToken, tokenAddress) || !sameAddress(liveCharter, charterAddress) || !charterCode || charterCode === '0x') throw new Error('The claim contracts could not be verified. Claims are disabled.');
  return { reserve, block };
}

export async function checkEligibility(id: bigint, stage: Stage, account: Address | null): Promise<Eligibility> {
  const blockNumber = await publicClient.getBlockNumber({ cacheTime: 0 });
  const base = { address: claimAddress, abi: claimAbi, blockNumber } as const;
  const [recorded, paid] = await Promise.all([
    publicClient.readContract({ ...base, functionName: 'claimant', args: [id] }),
    publicClient.readContract({ ...base, functionName: 'restClaimed', args: [id] }),
  ]);
  const result = (eligible: boolean, title: string, detail: string, charterBalance?: bigint): Eligibility => ({ id, stage, account, eligible, title, detail, amount: stage === 'instant' ? INSTANT : REST, charterBalance });
  if (stage === 'rest') {
    if (paid) return result(false, 'This Charter is fully paid.', 'Both portions have already been claimed. Check another Charter ID.');
    if (sameAddress(recorded, zeroAddress)) return result(false, 'Claim the first 10% first.', 'The current holder must make the initial claim before releasing this Charter.');
    if (!account) return result(false, 'The remaining 90% is unclaimed.', `Connect the original claimant wallet (${shortAddress(recorded)}) to check whether it holds zero Charters.`);
    if (!sameAddress(recorded, account)) return result(false, 'Use the original claimant wallet.', `The remaining BIC belongs to ${shortAddress(recorded)}. Switch accounts in your wallet and check again.`);
    const balance = await publicClient.readContract({ address: charterAddress, abi: charterAbi, functionName: 'balanceOf', args: [account], blockNumber });
    if (balance !== 0n) return result(false, 'The golden handcuffs are still on.', `Your wallet holds ${balance} Charter${balance === 1n ? '' : 's'}. All must leave this wallet before the remaining 90% can be claimed, including IDs above 1,032.`, balance);
    return result(true, 'The cuffs are off. BIC is ready.', 'You are the original claimant and this wallet holds no Charters.', balance);
  }
  if (!sameAddress(recorded, zeroAddress)) return result(false, 'The first 10% was already claimed.', `This ID is recorded to ${shortAddress(recorded)}. ${paid ? 'Its remaining 90% is also paid.' : 'Use “Release 90%” to check the remainder.'}`);
  // A missing/burned token may revert. Transport failures must remain errors, never “not owned”.
  let owner: Address;
  try {
    owner = await publicClient.readContract({ address: charterAddress, abi: charterAbi, functionName: 'ownerOf', args: [id], blockNumber });
  } catch (error) {
    if (error instanceof Error && /revert|nonexistent|invalid token/i.test(error.message)) return result(false, 'This Charter has no current owner.', 'It may be unminted, burned or revoked. An existing Charter must be held before the first claim.');
    throw error;
  }
  if (!account) return result(false, 'The first 10% is unclaimed.', `Connect the wallet that owns Charter #${id} to claim its first portion.`);
  if (!sameAddress(owner, account)) return result(false, 'This wallet does not own this Charter.', 'Switch to the current holder’s wallet or check another Charter ID. NFT approvals do not authorize a claim.');
  return result(true, 'Your first 10% is ready.', 'This claim records your wallet for the remaining 90%. Keep access to this wallet.');
}

export async function walletIdentity(provider: Provider): Promise<{ account: Address | null; chainId: number }> {
  const [accounts, chainId] = await Promise.all([provider.request({ method: 'eth_accounts' }), provider.request({ method: 'eth_chainId' })]);
  return { account: accounts[0] && isAddress(accounts[0]) ? accounts[0] : null, chainId: Number(chainId) };
}
export async function switchChain(provider: Provider) {
  try { await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: network.walletAddChain.chainId as `0x${string}` }] }); }
  catch (error) {
    if (Number((error as { code?: number }).code) !== 4902) throw error;
    await provider.request({ method: 'wallet_addEthereumChain', params: [network.walletAddChain] });
    await provider.request({ method: 'wallet_switchEthereumChain', params: [{ chainId: network.walletAddChain.chainId as `0x${string}` }] });
  }
}
export async function submitClaim(provider: Provider, expected: Eligibility): Promise<Hash> {
  const identity = await walletIdentity(provider);
  if (!identity.account || !expected.account || !sameAddress(identity.account, expected.account)) throw new Error('Your wallet account changed. Check eligibility again.');
  if (identity.chainId !== robinhood.id) throw new Error('Switch your wallet to Robinhood Chain and check again.');
  const state = await verifyDeployment();
  const fresh = await checkEligibility(expected.id, expected.stage, identity.account);
  if (!fresh.eligible) throw new Error(fresh.title + ' ' + fresh.detail);
  if (state.reserve < fresh.amount) throw new Error('The claim contract does not have enough BIC for this payout. Try again after funding is restored.');
  const { request } = await publicClient.simulateContract({
    address: claimAddress, abi: claimAbi, functionName: expected.stage === 'instant' ? 'claim' : 'claimRest',
    args: [[expected.id]], account: identity.account,
  });
  const current = await walletIdentity(provider);
  if (!current.account || !sameAddress(current.account, identity.account) || current.chainId !== robinhood.id) throw new Error('Your wallet changed during the check. Check eligibility again.');
  return createWalletClient({ chain: robinhood, transport: custom(provider) }).writeContract(request);
}
export function errorMessage(error: unknown): string {
  const e = error as { code?: number; message?: string; shortMessage?: string; cause?: { code?: number } };
  if (e.code === 4001 || e.cause?.code === 4001 || /user rejected|user denied/i.test(e.message || '')) return 'Request declined in your wallet. You can try again when ready.';
  if (e.code === -32002 || /already pending/i.test(e.message || '')) return 'A request is already open in your wallet. Open it to continue or cancel.';
  if (/insufficient funds/i.test(e.message || '')) return 'Your wallet needs ETH on Robinhood Chain to pay the network fee.';
  if (/http|fetch|timeout|network request|failed to get|limit exceeded/i.test(e.message || '')) return 'Unable to read Robinhood Chain. Check your connection and try again.';
  return e.shortMessage || e.message || 'The request could not be completed. Check your connection and try again.';
}

export function isExpectedClaim(log: Log, expected: Eligibility): boolean {
  if (!sameAddress(log.address, claimAddress)) return false;
  try {
    const event = decodeEventLog({ abi: claimAbi, data: log.data, topics: log.topics, eventName: 'Claimed' });
    return event.args.id === expected.id && sameAddress(event.args.account, expected.account!)
      && event.args.amount === expected.amount && event.args.rest === (expected.stage === 'rest');
  } catch { return false; }
}
