///|
pub struct Version {
  major : Int
  minor : Int
  patch : Int
  build : Build?
} derive(ToJson)

///|
pub impl Show for Version with fn output(self : Version, logger : &Logger) -> Unit {
  let string = if self.build is Some(build) {
    "\{self.major}.\{self.minor}.\{self.patch}+\{build.number}.\{build.commit}"
  } else {
    "\{self.major}.\{self.minor}.\{self.patch}"
  }
  logger.write_string(string)
}

///|
pub struct Build {
  number : Int
  commit : String
} derive(ToJson)

///|
pub let version : Version = try! Version::parse(version_string)

///|
fn parse_version_core(core : String) -> (Int, Int, Int) raise {
  let parts : Array[StringView] = core.split(".").collect()
  guard parts.length() == 3 else {
    fail("Invalid version string format: " + core)
  }
  (
    @string.parse_int(parts[0].to_owned()),
    @string.parse_int(parts[1].to_owned()),
    @string.parse_int(parts[2].to_owned()),
  )
}

///|
fn parse_version_build(build_text : String) -> Build raise {
  let parts : Array[StringView] = build_text.split(".").collect()
  guard parts.length() == 2 else {
    fail("Invalid version build format: " + build_text)
  }
  let commit = parts[1].to_owned()
  guard !commit.is_blank() else {
    fail("Invalid version build commit: " + build_text)
  }
  { number: @string.parse_int(parts[0].to_owned()), commit }
}

///|
pub fn Version::parse(string : String) -> Version raise {
  let parts : Array[StringView] = string.split("+").collect()
  guard parts.length() == 1 || parts.length() == 2 else {
    fail("Invalid version string format: " + string)
  }
  let (major, minor, patch) = parse_version_core(parts[0].to_owned())
  let build = if parts.length() == 2 {
    Some(parse_version_build(parts[1].to_owned()))
  } else {
    None
  }
  { major, minor, patch, build }
}

///|
pub impl Compare for Version with fn compare(self, other) -> Int {
  if self.major != other.major {
    return self.major.compare(other.major)
  }
  if self.minor != other.minor {
    return self.minor.compare(other.minor)
  }
  if self.patch != other.patch {
    return self.patch.compare(other.patch)
  }
  match (self.build, other.build) {
    (None, None) => 0
    (Some(_), None) => 1
    (None, Some(_)) => -1
    (Some(b1), Some(b2)) => return b1.number.compare(b2.number)
  }
}

///|
pub impl Eq for Version with fn equal(self, other) -> Bool {
  self.major == other.major &&
  self.minor == other.minor &&
  self.patch == other.patch &&
  (match (self.build, other.build) {
    (None, None) => true
    (Some(b1), Some(b2)) => b1.number == b2.number
    _ => false
  })
}
