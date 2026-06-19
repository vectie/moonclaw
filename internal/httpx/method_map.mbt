///|
priv struct MethodMap[T] {
  mut get : T?
  mut head : T?
  mut post : T?
  mut put : T?
  mut delete : T?
  mut connect : T?
  mut options : T?
  mut trace : T?
  mut patch : T?
}

///|
fn[T] MethodMap::get(self : MethodMap[T], method_ : Method) -> T? {
  match method_ {
    Get => self.get
    Head => self.head
    Post => self.post
    Put => self.put
    Delete => self.delete
    Connect => self.connect
    Options => self.options
    Trace => self.trace
    Patch => self.patch
  }
}

///|
fn[T] MethodMap::op_get(self : MethodMap[T], method_ : Method) -> T {
  guard self.get(method_) is Some(value) else {
    abort("MethodMap: no value for method \{method_}")
  }
  value
}

///|
fn[T] MethodMap::op_set(
  self : MethodMap[T],
  method_ : Method,
  value : T,
) -> Unit {
  match method_ {
    Get => self.get = Some(value)
    Head => self.head = Some(value)
    Post => self.post = Some(value)
    Put => self.put = Some(value)
    Delete => self.delete = Some(value)
    Connect => self.connect = Some(value)
    Options => self.options = Some(value)
    Trace => self.trace = Some(value)
    Patch => self.patch = Some(value)
  }
}

///|
fn[T] MethodMap::new() -> MethodMap[T] {
  {
    get: None,
    head: None,
    post: None,
    put: None,
    delete: None,
    connect: None,
    options: None,
    trace: None,
    patch: None,
  }
}

///|
fn[T] MethodMap::keys(self : MethodMap[T]) -> Iter[Method] {
  let mut i = 0
  Iter::new(() => {
    while i < methods.length() {
      let method_ = methods[i]
      i += 1
      if self.get(method_) is Some(_) {
        break Some(method_)
      }
    } nobreak {
      None
    }
  })
}
