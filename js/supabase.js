import { SUPABASE_CONFIG, isSupabaseConfigured } from './config.js';

export const supabase = isSupabaseConfigured && window.supabase
  ? window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey)
  : null;

export async function query(table, options = {}) {
  if (!supabase) return { data: null, error: null };
  let request = supabase.from(table).select(options.select || '*');
  if (options.order) request = request.order(options.order.column, { ascending: options.order.ascending ?? false });
  if (options.eq) Object.entries(options.eq).forEach(([key, value]) => { request = request.eq(key, value); });
  return request;
}

export async function insert(table, payload) {
  if (!supabase) return { data: null, error: new Error('Supabase belum dikonfigurasi.') };
  return supabase.from(table).insert(payload).select();
}

export async function update(table, id, payload) {
  if (!supabase) return { data: null, error: new Error('Supabase belum dikonfigurasi.') };
  return supabase.from(table).update(payload).eq('id', id).select();
}

export async function remove(table, id) {
  if (!supabase) return { data: null, error: new Error('Supabase belum dikonfigurasi.') };
  return supabase.from(table).delete().eq('id', id);
}

export async function saveSale(items) {
  if (!supabase) return { data: null, error: new Error('Supabase belum dikonfigurasi.') };
  return supabase.rpc('simpan_transaksi', { p_items: items });
}
