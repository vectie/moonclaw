///|
priv struct MethodSet {
  mut get : Bool
  mut head : Bool
  mut post : Bool
  mut put : Bool
  mut delete : Bool
  mut connect : Bool
  mut options : Bool
  mut trace : Bool
  mut patch : Bool
}

///|
fn MethodSet::op_get(self : MethodSet, method_ : Method) -> Bool {
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
fn MethodSet::op_set(self : MethodSet, method_ : Method, value : Bool) -> Unit {
  match method_ {
    Get => self.get = value
    Head => self.head = value
    Post => self.post = value
    Put => self.put = value
    Delete => self.delete = value
    Connect => self.connect = value
    Options => self.options = value
    Trace => self.trace = value
    Patch => self.patch = value
  }
}

///|
fn MethodSet::iterator(self : MethodSet) -> Iter[Method] {
  methods.iter().filter(method_ => self[method_])
}

///|
fn MethodSet::new() -> MethodSet {
  {
    get: false,
    head: false,
    post: false,
    put: false,
    delete: false,
    connect: false,
    options: false,
    trace: false,
    patch: false,
  }
}
