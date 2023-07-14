//! The Header Object follows the structure of the Parameter Object with the following changes:
//!
//!   1. name MUST NOT be specified, it is given in the corresponding headers map.
//!   2. in MUST NOT be specified, it is implicitly in header.
//!   3. All traits that are affected by the location MUST be applicable to a location of header (for example, style).
description: ?[]const u8 = null,
required: ?bool = null,
deprecated: ?bool = null,
allow_empty_value: ?bool = null,
