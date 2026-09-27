export const SUPABASE_CONFIG = {
  url: 'https://isdidddvzajkfdhdejtz.supabase.co',
  anonKey: 'sb_publishable_H5rcCoUBNkbIkoYRxuuYGQ_MdfCy9bM'
};

export const isSupabaseConfigured = !SUPABASE_CONFIG.url.includes('YOUR_PROJECT') && !SUPABASE_CONFIG.anonKey.includes('YOUR_');
