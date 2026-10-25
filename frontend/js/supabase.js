import { SUPABASE_CONFIG, isSupabaseConfigured } from './config.js';

export const supabase = isSupabaseConfigured && window.supabase
  ? window.supabase.createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey)
  : null;

async function resultOf(request) {
  const { data, error } = await request;
  if (error) throw error;
  return data;
}

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

const number = value => Number(value || 0);
const toCategory = row => ({ id: row.id, name: row.nama, color: row.warna });
const toPartner = row => ({ id: row.id, name: row.nama, phone: row.telepon, email: row.email || '', address: row.alamat || '', status: row.status === 'aktif' ? 'active' : 'inactive' });
const toProduct = row => ({ id: row.id, sku: row.sku, name: row.nama, categoryId: row.kategori_id, partnerId: row.mitra_id, price: number(row.harga_jual), commission: number(row.persentase_komisi), stock: number(row.stok), minStock: number(row.stok_minimum), active: row.aktif });
const toPayment = row => ({ id: row.id, partnerId: row.mitra_id, amount: number(row.jumlah), method: ({ transfer: 'Transfer Bank', tunai: 'Tunai', e_wallet: 'E-wallet' })[row.metode] || row.metode, reference: row.referensi || '', createdAt: row.tanggal_bayar });

export async function loadRemoteStore() {
  if (!supabase) throw new Error('Supabase belum dikonfigurasi atau SDK belum dimuat.');
  const [categories, partners, products, transactions, details, payments] = await Promise.all([
    resultOf(supabase.from('kategori').select('*').order('nama')),
    resultOf(supabase.from('mitra').select('*').order('nama')),
    resultOf(supabase.from('produk').select('*').order('nama')),
    resultOf(supabase.from('transaksi').select('*').order('terjadi_pada', { ascending: false })),
    resultOf(supabase.from('detail_transaksi').select('*')),
    resultOf(supabase.from('pembayaran_mitra').select('*').order('tanggal_bayar', { ascending: false }))
  ]);

  return {
    categories: categories.map(toCategory),
    partners: partners.map(toPartner),
    products: products.map(toProduct),
    sales: transactions.map(row => ({
      id: row.nomor_transaksi,
      databaseId: row.id,
      createdAt: row.terjadi_pada,
      items: details.filter(item => item.transaksi_id === row.id).map(item => ({ productId: item.produk_id, quantity: number(item.jumlah), price: number(item.harga_satuan), commission: number(item.persentase_komisi) })),
      total: number(row.total_bruto),
      commission: number(row.total_komisi),
      partnerDue: number(row.total_hak_mitra),
      status: row.status === 'berhasil' ? 'paid' : 'cancelled'
    })),
    payments: payments.map(toPayment)
  };
}

export async function syncRemoteStore(current, previous) {
  if (!supabase) throw new Error('Supabase belum dikonfigurasi atau SDK belum dimuat.');
  const old = previous || { categories: [], partners: [], products: [], sales: [], payments: [] };
  const addedSales = current.sales.filter(item => !old.sales.some(saved => saved.id === item.id));
  const hasAddedSales = addedSales.length > 0;
  const saveRows = async (table, rows, oldRows, toRow, ignoreStock = false) => {
    for (const row of rows) {
      const before = oldRows.find(saved => saved.id === row.id);
      const comparable = ignoreStock && before ? { ...row, stock: before.stock } : row;
      if (before && JSON.stringify(comparable) === JSON.stringify(before)) continue;
      await resultOf(supabase.from(table).upsert(toRow(comparable)).select().single());
    }
  };

  await saveRows('kategori', current.categories, old.categories, row => ({ id: row.id, nama: row.name, warna: row.color }));
  await saveRows('mitra', current.partners, old.partners, row => ({ id: row.id, nama: row.name, telepon: row.phone, email: row.email || null, alamat: row.address || null, status: row.status === 'inactive' ? 'nonaktif' : 'aktif' }));
  await saveRows('produk', current.products, old.products, row => ({ id: row.id, sku: row.sku, nama: row.name, kategori_id: row.categoryId, mitra_id: row.partnerId, harga_jual: row.price, persentase_komisi: row.commission, stok: row.stock, stok_minimum: row.minStock, aktif: row.active }), hasAddedSales);

  for (const sale of addedSales) {
    await resultOf(saveSale(sale.items.map(item => ({ produk_id: item.productId, jumlah: item.quantity }))));
  }

  await saveRows('pembayaran_mitra', current.payments, old.payments, row => ({ id: row.id, mitra_id: row.partnerId, tanggal_bayar: row.createdAt, jumlah: row.amount, metode: ({ 'Transfer Bank': 'transfer', Tunai: 'tunai', 'E-wallet': 'e_wallet' })[row.method] || 'transfer', referensi: row.reference || null }));

  for (const row of old.products) {
    if (!current.products.some(item => item.id === row.id)) await resultOf(remove('produk', row.id));
  }
  for (const row of old.categories) {
    if (!current.categories.some(item => item.id === row.id)) await resultOf(remove('kategori', row.id));
  }

  return loadRemoteStore();
}
