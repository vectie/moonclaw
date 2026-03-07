///|
pub enum Direction {
  Vertical
  Horizontal
}

///|
pub(all) struct Container {
  children : Array[Component]
  direction : Direction
  mut focused_index : Int
}

///|
pub enum Component {
  TextComponent(Text)
  ContainerComponent(Container)
  EditorComponent(Editor)
  LoaderComponent(Loader)
  SpacerComponent(Spacer)
  BoxComponent(Box)
}

///|
pub fn Container::new(direction? : Direction = Vertical) -> Container {
  Container::{ children: [], direction, focused_index: 0 }
}

///|
pub fn Container::add_child(self : Container, child : Component) -> Unit {
  self.children.push(child)
}

///|
pub fn Container::clear(self : Container) -> Unit {
  self.children.clear()
}

///|
pub fn Container::remove_child(self : Container, index : Int) -> Unit {
  if index >= 0 && index < self.children.length() {
    ignore(self.children.remove(index))
  }
}

///|
pub fn Container::child_count(self : Container) -> Int {
  self.children.length()
}

///|
pub fn Container::get_child(self : Container, index : Int) -> Component? {
  if index >= 0 && index < self.children.length() {
    Some(self.children[index])
  } else {
    None
  }
}

///|
pub fn Container::get_focused_child(self : Container) -> Component? {
  self.get_child(self.focused_index)
}

///|
pub fn Container::focus_next(self : Container) -> Unit {
  let mut idx = self.focused_index + 1
  while idx < self.children.length() {
    match self.children[idx] {
      EditorComponent(_) => {
        self.focused_index = idx
        return
      }
      ContainerComponent(c) => {
        self.focused_index = idx
        c.focus_next()
        return
      }
      _ => idx += 1
    }
  }
}

///|
pub fn Container::focus_prev(self : Container) -> Unit {
  let mut idx = self.focused_index - 1
  while idx >= 0 {
    match self.children[idx] {
      EditorComponent(_) => {
        self.focused_index = idx
        return
      }
      ContainerComponent(c) => {
        self.focused_index = idx
        c.focus_prev()
        return
      }
      _ => idx -= 1
    }
  }
}

///|
pub async fn Container::render(
  self : Container,
  output : @stdio.Output,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  let mut current_y = y
  let mut current_x = x
  match self.direction {
    Vertical =>
      for child in self.children {
        let child_height = child.get_preferred_height(width)
        if current_y + child_height > y + height {
          break
        }
        child.render(output, current_x, current_y, width, child_height)
        current_y += child_height
      }
    Horizontal => {
      let child_width = width / self.children.length().max(1)
      for child in self.children {
        if current_x + child_width > x + width {
          break
        }
        child.render(output, current_x, current_y, child_width, height)
        current_x += child_width
      }
    }
  }
}

///|
pub async fn Component::render(
  self : Component,
  output : @stdio.Output,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Unit {
  match self {
    TextComponent(t) => t.render(output, x, y, width, height)
    ContainerComponent(c) => c.render(output, x, y, width, height)
    EditorComponent(e) => e.render(output, x, y, width, height)
    LoaderComponent(l) => l.render(output, x, y, width, height)
    SpacerComponent(s) => s.render(output, x, y, width, height)
    BoxComponent(b) => b.render(output, x, y, width, height)
  }
}

///|
pub fn Component::get_preferred_height(self : Component, width : Int) -> Int {
  match self {
    TextComponent(t) => t.get_preferred_height(width)
    ContainerComponent(c) => c.get_preferred_height(width)
    EditorComponent(e) => e.get_preferred_height(width)
    LoaderComponent(l) => l.get_preferred_height(width)
    SpacerComponent(s) => s.get_preferred_height(width)
    BoxComponent(b) => b.get_preferred_height(width)
  }
}

///|
pub fn Container::get_preferred_height(self : Container, width : Int) -> Int {
  let mut total = 0
  match self.direction {
    Vertical =>
      for child in self.children {
        total += child.get_preferred_height(width)
      }
    Horizontal => {
      let mut max_h = 0
      for child in self.children {
        let h = child.get_preferred_height(width)
        if h > max_h {
          max_h = h
        }
      }
      total = max_h
    }
  }
  total
}

///|
pub fn Component::handle_key(self : Component, key : Key) -> Bool {
  match self {
    EditorComponent(e) => e.handle_key(key)
    ContainerComponent(c) =>
      match c.get_focused_child() {
        Some(child) => child.handle_key(key)
        None => false
      }
    _ => false
  }
}

///|
pub fn Component::is_focusable(self : Component) -> Bool {
  match self {
    EditorComponent(_) => true
    ContainerComponent(c) => {
      for child in c.children {
        if child.is_focusable() {
          return true
        }
      }
      false
    }
    _ => false
  }
}
