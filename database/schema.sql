-- ConsignU - Schema PostgreSQL untuk Supabase
-- Jalankan seluruh file ini melalui Supabase SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.mitra (
  id uuid primary key default gen_random_uuid(),
  nama text not null,
  telepon text not null,
  email text,
  alamat text,
  status text not null default 'aktif' check (status in ('aktif', 'nonaktif')),
  created_at timestamptz not null default now()
);

create table if not exists public.kategori (
  id uuid primary key default gen_random_uuid(),
  nama text not null unique,
  warna text not null default '#5546d8',
  created_at timestamptz not null default now()
);

create table if not exists public.produk (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  nama text not null,
  kategori_id uuid not null references public.kategori(id) on update cascade on delete restrict,
  mitra_id uuid not null references public.mitra(id) on update cascade on delete restrict,
  harga_jual numeric(14,2) not null check (harga_jual > 0),
  persentase_komisi numeric(5,2) not null default 20 check (persentase_komisi between 0 and 100),
  stok integer not null default 0 check (stok >= 0),
  stok_minimum integer not null default 5 check (stok_minimum >= 0),
  aktif boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.transaksi (
  id uuid primary key default gen_random_uuid(),
  nomor_transaksi text not null unique,
  terjadi_pada timestamptz not null default now(),
  total_bruto numeric(14,2) not null default 0 check (total_bruto >= 0),
  total_komisi numeric(14,2) not null default 0 check (total_komisi >= 0),
  total_hak_mitra numeric(14,2) not null default 0 check (total_hak_mitra >= 0),
  status text not null default 'berhasil' check (status in ('berhasil', 'dibatalkan')),
  created_at timestamptz not null default now()
);

create table if not exists public.detail_transaksi (
  id uuid primary key default gen_random_uuid(),
  transaksi_id uuid not null references public.transaksi(id) on delete cascade,
  produk_id uuid not null references public.produk(id) on update cascade on delete restrict,
  jumlah integer not null check (jumlah > 0),
  harga_satuan numeric(14,2) not null check (harga_satuan > 0),
  persentase_komisi numeric(5,2) not null check (persentase_komisi between 0 and 100),
  subtotal numeric(14,2) generated always as (jumlah * harga_satuan) stored,
  nilai_komisi numeric(14,2) generated always as (jumlah * harga_satuan * persentase_komisi / 100) stored
);

create table if not exists public.pembayaran_mitra (
  id uuid primary key default gen_random_uuid(),
  mitra_id uuid not null references public.mitra(id) on update cascade on delete restrict,
  tanggal_bayar timestamptz not null default now(),
  jumlah numeric(14,2) not null check (jumlah > 0),
  metode text not null check (metode in ('transfer', 'tunai', 'e_wallet')),
  referensi text,
  catatan text,
  created_at timestamptz not null default now()
);

create index if not exists idx_produk_mitra on public.produk(mitra_id);
create index if not exists idx_produk_kategori on public.produk(kategori_id);
create index if not exists idx_transaksi_tanggal on public.transaksi(terjadi_pada desc);
create index if not exists idx_detail_produk on public.detail_transaksi(produk_id);
create index if not exists idx_pembayaran_mitra on public.pembayaran_mitra(mitra_id, tanggal_bayar desc);

-- RPC atomik: validasi stok, insert transaksi/detail, lalu kurangi stok dalam satu transaksi database.
create or replace function public.simpan_transaksi(p_items jsonb)
returns uuid language plpgsql security invoker set search_path = public as $$
declare
  v_transaksi_id uuid;
  v_nomor text := 'TRX-' || to_char(now(), 'YYYYMMDD-HH24MISS');
  v_item jsonb;
  v_produk public.produk%rowtype;
  v_total numeric(14,2) := 0;
  v_komisi numeric(14,2) := 0;
  v_jumlah integer;
  v_subtotal numeric(14,2);
  v_nilai_komisi numeric(14,2);
begin
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Transaksi harus memiliki item'; end if;
  insert into public.transaksi(nomor_transaksi) values (v_nomor) returning id into v_transaksi_id;
  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_produk from public.produk where id = (v_item->>'produk_id')::uuid and aktif = true for update;
    if not found then raise exception 'Produk tidak ditemukan atau tidak aktif'; end if;
    v_jumlah := (v_item->>'jumlah')::integer;
    if v_jumlah <= 0 or v_produk.stok < v_jumlah then raise exception 'Stok produk % tidak mencukupi', v_produk.nama; end if;
    v_subtotal := v_jumlah * v_produk.harga_jual;
    v_nilai_komisi := v_subtotal * v_produk.persentase_komisi / 100;
    insert into public.detail_transaksi(transaksi_id, produk_id, jumlah, harga_satuan, persentase_komisi) values (v_transaksi_id, v_produk.id, v_jumlah, v_produk.harga_jual, v_produk.persentase_komisi);
    update public.produk set stok = stok - v_jumlah where id = v_produk.id;
    v_total := v_total + v_subtotal; v_komisi := v_komisi + v_nilai_komisi;
  end loop;
  update public.transaksi set total_bruto = v_total, total_komisi = v_komisi, total_hak_mitra = v_total - v_komisi where id = v_transaksi_id;
  return v_transaksi_id;
exception when others then raise;
end; $$;

create or replace view public.v_ringkasan_mitra as
select m.id as mitra_id, m.nama,
  coalesce(sum(d.subtotal), 0) as total_bruto,
  coalesce(sum(d.nilai_komisi), 0) as total_komisi,
  coalesce(sum(d.subtotal - d.nilai_komisi), 0) as total_hak_mitra,
  coalesce((select sum(p.jumlah) from public.pembayaran_mitra p where p.mitra_id = m.id), 0) as total_dibayar
from public.mitra m left join public.produk pr on pr.mitra_id = m.id left join public.detail_transaksi d on d.produk_id = pr.id
 group by m.id, m.nama;

alter table public.mitra enable row level security;
alter table public.kategori enable row level security;
alter table public.produk enable row level security;
alter table public.transaksi enable row level security;
alter table public.detail_transaksi enable row level security;
alter table public.pembayaran_mitra enable row level security;

-- Untuk demo tugas akhir, akses diberikan kepada user yang sudah login melalui Supabase Auth.
-- Ganti kebijakan ini dengan pembatasan berbasis role bila aplikasi sudah memiliki multi-role.
drop policy if exists "authenticated can read mitra" on public.mitra;
drop policy if exists "authenticated can manage mitra" on public.mitra;
drop policy if exists "authenticated can read kategori" on public.kategori;
drop policy if exists "authenticated can manage kategori" on public.kategori;
drop policy if exists "authenticated can read produk" on public.produk;
drop policy if exists "authenticated can manage produk" on public.produk;
drop policy if exists "authenticated can read transaksi" on public.transaksi;
drop policy if exists "authenticated can insert transaksi" on public.transaksi;
drop policy if exists "authenticated can read detail" on public.detail_transaksi;
drop policy if exists "authenticated can insert detail" on public.detail_transaksi;
drop policy if exists "authenticated can read pembayaran" on public.pembayaran_mitra;
drop policy if exists "authenticated can manage pembayaran" on public.pembayaran_mitra;

create policy "authenticated can read mitra" on public.mitra for select to authenticated using (true);
create policy "authenticated can manage mitra" on public.mitra for all to authenticated using (true) with check (true);
create policy "authenticated can read kategori" on public.kategori for select to authenticated using (true);
create policy "authenticated can manage kategori" on public.kategori for all to authenticated using (true) with check (true);
create policy "authenticated can read produk" on public.produk for select to authenticated using (true);
create policy "authenticated can manage produk" on public.produk for all to authenticated using (true) with check (true);
create policy "authenticated can read transaksi" on public.transaksi for select to authenticated using (true);
create policy "authenticated can insert transaksi" on public.transaksi for insert to authenticated with check (true);
create policy "authenticated can read detail" on public.detail_transaksi for select to authenticated using (true);
create policy "authenticated can insert detail" on public.detail_transaksi for insert to authenticated with check (true);
create policy "authenticated can read pembayaran" on public.pembayaran_mitra for select to authenticated using (true);
create policy "authenticated can manage pembayaran" on public.pembayaran_mitra for all to authenticated using (true) with check (true);
