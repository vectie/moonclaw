///|
priv struct Entry[T] {
  mut accessed : Int
  value : T
}

///|
impl[T : ToJson] ToJson for Entry[T] with fn to_json(self : Entry[T]) -> Json {
  self.value.to_json()
}

///|
struct Cache[K, V] {
  mut timestamp : Int
  cache : Map[K, Entry[V]]
  max_size : Int
}

///|
pub fn[K : Eq + Hash, V] cache(max_size? : Int = 100) -> Cache[K, V] {
  { timestamp: 0, cache: {}, max_size }
}

///|
pub fn[K : Eq + Hash, V] Cache::get(self : Cache[K, V], key : K) -> V? {
  match self.cache.get(key) {
    None => None
    Some(entry) => {
      entry.accessed = self.timestamp
      self.timestamp += 1
      Some(entry.value)
    }
  }
}

///|
pub fn[K : Eq + Hash, V] Cache::op_get(self : Cache[K, V], key : K) -> V {
  self.get(key).unwrap()
}

///|
pub fn[K : Eq + Hash, V] Cache::op_set(
  self : Cache[K, V],
  key : K,
  value : V,
) -> Unit {
  if self.cache.length() >= self.max_size {
    self.evict()
  }
  self.cache[key] = { accessed: self.timestamp, value }
  self.timestamp += 1
}

///|
fn[K : Eq + Hash, V] Cache::evict(self : Cache[K, V]) -> Unit {
  let mut oldest = None
  for k, v in self.cache {
    match oldest {
      None => oldest = Some((k, v))
      Some((_, ov)) => if v.accessed < ov.accessed { oldest = Some((k, v)) }
    }
  }
  if oldest is Some((k, _)) {
    self.cache.remove(k)
  }
}

///|
pub impl[K : Show, V : ToJson] ToJson for Cache[K, V] with fn to_json(
  self : Cache[K, V],
) -> Json {
  self.cache.to_json()
}
