import { useCallback, useEffect, useRef, useState } from 'react';
import type { Address } from 'viem';
import { errorMessage, walletIdentity, type Provider } from './chain';

type WalletInfo = { uuid: string; name: string };
export type AvailableWallet = { info: WalletInfo; provider: Provider };
declare global { interface Window { ethereum?: Provider } }

export function useWallet() {
  const [available, setAvailable] = useState<AvailableWallet[]>([]);
  const [provider, setProvider] = useState<Provider | null>(null);
  const [account, setAccount] = useState<Address | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState('');
  const connectSequence = useRef(0);
  const identitySequence = useRef(0);
  useEffect(() => {
    const announce = (event: Event) => {
      const detail = (event as CustomEvent<AvailableWallet>).detail;
      if (!detail?.provider?.request || !detail.info?.uuid || !detail.info?.name) return;
      setAvailable(items => items.some(w => w.info.uuid === detail.info.uuid) ? items : [...items, detail]);
    };
    window.addEventListener('eip6963:announceProvider', announce);
    window.dispatchEvent(new Event('eip6963:requestProvider'));
    return () => window.removeEventListener('eip6963:announceProvider', announce);
  }, []);
  const refresh = useCallback(async (p: Provider) => {
    const sequence = ++identitySequence.current;
    const identity = await walletIdentity(p);
    if (sequence !== identitySequence.current) return identity;
    setAccount(identity.account); setChainId(identity.chainId);
    return identity;
  }, []);
  useEffect(() => {
    if (!provider) return;
    const change = () => { setAccount(null); setChainId(null); refresh(provider).catch(e => setError(errorMessage(e))); };
    const disconnect = () => { ++identitySequence.current; setAccount(null); setChainId(null); setProvider(null); };
    provider.on?.('accountsChanged', change);
    provider.on?.('chainChanged', change);
    provider.on?.('disconnect', disconnect);
    return () => {
      ++identitySequence.current;
      provider.removeListener?.('accountsChanged', change);
      provider.removeListener?.('chainChanged', change);
      provider.removeListener?.('disconnect', disconnect);
    };
  }, [provider, refresh]);
  async function connect(p: Provider) {
    const sequence = ++connectSequence.current;
    setConnecting(true); setError('');
    try {
      await p.request({ method: 'eth_requestAccounts' });
      const identity = await walletIdentity(p);
      if (sequence !== connectSequence.current) return false;
      if (!identity.account) throw new Error('No account was shared. Select an account in your wallet and try again.');
      setProvider(p); setAccount(identity.account); setChainId(identity.chainId);
      return true;
    } catch (e) { if (sequence === connectSequence.current) setError(errorMessage(e)); return false; }
    finally { if (sequence === connectSequence.current) setConnecting(false); }
  }
  function disconnect() { ++identitySequence.current; ++connectSequence.current; setConnecting(false); setProvider(null); setAccount(null); setChainId(null); setError(''); }
  const choices = available.length ? available : window.ethereum ? [{ info: { uuid: 'injected', name: 'Browser wallet' }, provider: window.ethereum }] : [];
  return { account, chainId, provider, connecting, error, choices, connect, disconnect, refresh, clearError: () => setError('') };
}
export type Wallet = ReturnType<typeof useWallet>;
