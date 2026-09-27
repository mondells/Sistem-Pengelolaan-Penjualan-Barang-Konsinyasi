# ConsignU

ConsignU adalah aplikasi manajemen penjualan barang konsinyasi untuk simulasi department store. Aplikasi dibuat dengan HTML, CSS, dan JavaScript murni. Supabase PostgreSQL digunakan sebagai database dan backend-as-a-service.

## Struktur sederhana

```text
ConsignU/
|-- index.html              # halaman aplikasi dan layout utama
|-- css/
|   `-- style.css           # tampilan dashboard responsif
|-- js/
|   |-- app.js              # routing hash, UI, CRUD demo, POS, laporan
|   |-- config.js           # URL dan anon/publishable key Supabase
|   `-- supabase.js         # client Supabase, CRUD, dan RPC transaksi
|-- database/
|   `-- schema.sql          # tabel PostgreSQL, view, RPC, index, dan RLS
`-- README.md
```

Tidak ada backend Node.js atau server lokal. `app.js` adalah pengendali aplikasi di browser, sedangkan fungsi backend dijalankan oleh Supabase melalui PostgreSQL, RLS, dan RPC `simpan_transaksi`.

## Menyiapkan Supabase

1. Buat project baru di Supabase.
2. Buka **SQL Editor**, tempel seluruh isi `database/schema.sql`, lalu jalankan.
3. Buka **Project Settings > API**.
4. Salin Project URL dan publishable/anon key ke `js/config.js`.
5. Jangan gunakan `service_role` key di frontend.
6. Untuk penggunaan dengan RLS, buat user melalui Supabase Auth dan gunakan sesi login sebelum mengakses data produksi.

## Menjalankan aplikasi

Buka `index.html` langsung di Chrome, atau klik kanan `index.html` di VS Code lalu pilih **Open with Live Server**. Sebelum konfigurasi Supabase diisi, aplikasi menggunakan data demo di `localStorage` agar semua alur POS dapat dicoba. Setelah integrasi Supabase diaktifkan, gunakan helper di `js/supabase.js` dan RPC transaksi atomik di `database/schema.sql` sebagai jalur data produksi.

### Menjalankan dengan Live Server

1. Buka folder proyek ini di Visual Studio Code.
2. Buka Extensions, cari **Live Server** dari Ritwick Dey, lalu instal.
3. Klik kanan `index.html` pada Explorer.
4. Pilih **Open with Live Server**.
5. Chrome akan membuka alamat seperti `http://127.0.0.1:5500/index.html`.

Jika hanya ingin mencoba tampilan dan alur demo, langkah ini sudah cukup. Data demo disimpan di browser, bukan di Supabase.

### Mengisi database Supabase

1. Masuk ke dashboard project Supabase.
2. Buka **SQL Editor > New query**.
3. Salin seluruh isi `database/schema.sql` ke editor.
4. Klik **Run** dan pastikan tidak ada pesan error.
5. Periksa tabel pada **Table Editor**.

RLS pada schema hanya mengizinkan user dengan role `authenticated`. Karena aplikasi saat ini belum memiliki halaman login, UI masih menggunakan mode demo. Untuk mode produksi, tambahkan Supabase Auth dan panggil `supabase.auth.signInWithPassword()` sebelum membaca atau mengubah tabel. Publishable/anon key boleh berada di frontend, tetapi `service_role` key tidak boleh.

## Menghubungkan ke GitHub

### Cara melalui VS Code

1. Buat repository baru di GitHub, misalnya `consignu`.
2. Jangan centang pembuatan README atau `.gitignore` jika folder lokal sudah berisi file tersebut.
3. Di VS Code, buka folder proyek `sistem_konsinyasi_barang_dagang`.
4. Buka panel **Source Control** di sebelah kiri.
5. Klik **Initialize Repository**.
6. Klik tanda `+` pada **Changes** untuk melakukan stage semua file.
7. Tulis pesan commit, misalnya `Initial ConsignU application`, lalu klik **Commit**.
8. Klik **Publish Branch** atau **Publish to GitHub**.
9. Login ke GitHub saat diminta, pilih repository yang baru dibuat, lalu pilih **Private** atau **Public**.

Setelah berhasil, perubahan berikutnya dilakukan dengan urutan **Source Control > Stage > Commit > Sync Changes**.

### Menjalankan dari GitHub Pages

1. Buka repository di GitHub.
2. Masuk ke **Settings > Pages**.
3. Pada **Build and deployment**, pilih **Deploy from a branch**.
4. Pilih branch `main` dan folder `/ (root)`, lalu klik **Save**.
5. Tunggu beberapa saat, lalu buka URL GitHub Pages yang diberikan.

Karena aplikasi menggunakan hash route seperti `#dashboard` dan `#pos`, navigasi tetap dapat bekerja di GitHub Pages. Pastikan URL Supabase dan publishable key pada `js/config.js` sudah benar sebelum melakukan publish.

## Logika akuntansi

- Penjualan bruto = jumlah terjual x harga jual.
- Komisi toko = penjualan bruto x persentase komisi.
- Hak mitra = penjualan bruto - komisi toko.
- RPC `simpan_transaksi` mengunci stok, memvalidasi jumlah, menyimpan transaksi dan detail, lalu mengurangi stok dalam satu transaksi PostgreSQL.