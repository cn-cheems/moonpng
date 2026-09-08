///|
extern "js" fn browser_bind_file_handler(
  handler : (String, Bytes) -> Unit,
) -> Unit =
  #| function(handler) {
  #|   const input = document.getElementById("file-input");
  #|   const button = document.getElementById("choose-file");
  #|   const zone = document.getElementById("drop-zone");
  #|   const load = async (file) => {
  #|     if (!file) return;
  #|     try {
  #|       const data = new Uint8Array(await file.arrayBuffer());
  #|       handler(file.name, data);
  #|     } catch (error) {
  #|       const status = document.getElementById("status");
  #|       status.dataset.tone = "error";
  #|       status.textContent = `读取文件失败：${error instanceof Error ? error.message : String(error)}`;
  #|     }
  #|   };
  #|   button.addEventListener("click", () => {
  #|     input.value = "";
  #|     input.click();
  #|   });
  #|   input.addEventListener("change", () => load(input.files[0]));
  #|   zone.addEventListener("dragover", (event) => {
  #|     event.preventDefault();
  #|     zone.dataset.dragging = "true";
  #|   });
  #|   zone.addEventListener("dragleave", () => delete zone.dataset.dragging);
  #|   zone.addEventListener("drop", (event) => {
  #|     event.preventDefault();
  #|     delete zone.dataset.dragging;
  #|     load(event.dataTransfer.files[0]);
  #|   });
  #| }

///|
extern "js" fn browser_set_busy(busy : Bool) -> Unit =
  #| function(busy) {
  #|   document.getElementById("workspace").setAttribute("aria-busy", String(busy));
  #|   document.getElementById("choose-file").disabled = busy;
  #| }

///|
extern "js" fn browser_set_status(tone : String, message : String) -> Unit =
  #| function(tone, message) {
  #|   const status = document.getElementById("status");
  #|   status.dataset.tone = tone;
  #|   status.textContent = message;
  #| }

///|
extern "js" fn browser_begin_file(name : String, source_size : Int) -> Unit =
  #| function(name, sourceSize) {
  #|   document.getElementById("file-name").textContent = name;
  #|   document.getElementById("source-size").textContent = sourceSize.toLocaleString() + " B";
  #|   for (const id of ["dimensions", "bit-depth", "color-format", "interlace", "decoded-size", "encoded-size", "chunk-count", "text-count"]) {
  #|     document.getElementById(id).textContent = "—";
  #|   }
  #|   const link = document.getElementById("download");
  #|   link.hidden = true;
  #|   if (globalThis.__moonpngDownloadUrl) {
  #|     URL.revokeObjectURL(globalThis.__moonpngDownloadUrl);
  #|     globalThis.__moonpngDownloadUrl = undefined;
  #|   }
  #|   document.getElementById("preview").hidden = true;
  #|   const empty = document.getElementById("preview-empty");
  #|   empty.hidden = false;
  #|   empty.textContent = "正在解码像素…";
  #| }

///|
extern "js" fn browser_clear_chunks() -> Unit =
  #| function() {
  #|   document.getElementById("chunk-rows").replaceChildren();
  #| }

///|
extern "js" fn browser_clear_text_entries() -> Unit =
  #| function() {
  #|   document.getElementById("text-rows").replaceChildren();
  #|   document.getElementById("text-empty").hidden = false;
  #| }

///|
extern "js" fn browser_add_text_entry(
  format : String,
  keyword : String,
  text : String,
  language : String,
) -> Unit =
  #| function(format, keyword, text, language) {
  #|   const row = document.createElement("tr");
  #|   for (const [value, className] of [[format, ""], [keyword, "keyword-cell"], [text, "text-cell"], [language || "—", ""]]) {
  #|     const cell = document.createElement("td");
  #|     cell.textContent = value;
  #|     cell.title = value;
  #|     if (className) cell.className = className;
  #|     row.appendChild(cell);
  #|   }
  #|   document.getElementById("text-rows").appendChild(row);
  #|   document.getElementById("text-empty").hidden = true;
  #| }

///|
extern "js" fn browser_add_chunk(
  index : Int,
  kind : String,
  length : Int,
  offset : Int,
  critical : Bool,
) -> Unit =
  #| function(index, kind, length, offset, critical) {
  #|   const row = document.createElement("tr");
  #|   const values = [String(index + 1).padStart(2, "0"), kind, length.toLocaleString(), offset.toLocaleString()];
  #|   for (const value of values) {
  #|     const cell = document.createElement("td");
  #|     cell.textContent = value;
  #|     row.appendChild(cell);
  #|   }
  #|   const role = document.createElement("td");
  #|   role.textContent = critical ? "关键" : "辅助";
  #|   role.dataset.role = critical ? "critical" : "ancillary";
  #|   row.appendChild(role);
  #|   const crc = document.createElement("td");
  #|   crc.textContent = "通过";
  #|   crc.className = "crc-ok";
  #|   row.appendChild(crc);
  #|   document.getElementById("chunk-rows").appendChild(row);
  #| }

///|
extern "js" fn browser_present_summary(
  name : String,
  source_size : Int,
  width : UInt,
  height : UInt,
  bit_depth : Byte,
  color_format : String,
  interlace : String,
  decoded_size : Int,
  encoded_size : Int,
  chunk_count : Int,
  text_count : Int,
) -> Unit =
  #| function(name, sourceSize, width, height, bitDepth, colorFormat, interlace, decodedSize, encodedSize, chunkCount, textCount) {
  #|   const values = {
  #|     "file-name": name,
  #|     "source-size": sourceSize.toLocaleString() + " B",
  #|     "dimensions": `${width} × ${height}`,
  #|     "bit-depth": bitDepth + " bit",
  #|     "color-format": colorFormat,
  #|     "interlace": interlace,
  #|     "decoded-size": decodedSize.toLocaleString() + " B",
  #|     "encoded-size": encodedSize.toLocaleString() + " B",
  #|     "chunk-count": String(chunkCount),
  #|     "text-count": String(textCount),
  #|   };
  #|   for (const [id, value] of Object.entries(values)) {
  #|     document.getElementById(id).textContent = value;
  #|   }
  #| }

///|
extern "js" fn browser_draw_rgba(
  width : UInt,
  height : UInt,
  pixels : Bytes,
) -> Bool =
  #| function(width, height, pixels) {
  #|   try {
  #|     const canvas = document.getElementById("preview");
  #|     const context = canvas.getContext("2d", { alpha: true });
  #|     canvas.width = width;
  #|     canvas.height = height;
  #|     const rgba = new Uint8ClampedArray(pixels.buffer, pixels.byteOffset, pixels.byteLength);
  #|     context.putImageData(new ImageData(rgba, width, height), 0, 0);
  #|     document.getElementById("preview-empty").hidden = true;
  #|     canvas.hidden = false;
  #|     return true;
  #|   } catch (_) {
  #|     document.getElementById("preview").hidden = true;
  #|     const empty = document.getElementById("preview-empty");
  #|     empty.hidden = false;
  #|     empty.textContent = "图片已解码，但尺寸超过当前浏览器的画布能力。";
  #|     return false;
  #|   }
  #| }

///|
extern "js" fn browser_set_download(data : Bytes, name : String) -> Unit =
  #| function(data, name) {
  #|   if (globalThis.__moonpngDownloadUrl) URL.revokeObjectURL(globalThis.__moonpngDownloadUrl);
  #|   const url = URL.createObjectURL(new Blob([data], { type: "image/png" }));
  #|   globalThis.__moonpngDownloadUrl = url;
  #|   const link = document.getElementById("download");
  #|   link.href = url;
  #|   const stem = name.toLowerCase().endsWith(".png") ? name.slice(0, -4) : name;
  #|   link.download = `${stem}-moonpng.png`;
  #|   link.hidden = false;
  #| }

///|
fn color_format_name(color_type : Byte) -> String {
  match color_type.to_uint() {
    0U => "灰度"
    2U => "真彩色 RGB"
    3U => "索引色"
    4U => "灰度 + Alpha"
    6U => "真彩色 RGBA"
    value => "未知格式（\{value}）"
  }
}

///|
fn interlace_name(interlace : Byte) -> String {
  if interlace == b'\x01' {
    "Adam7"
  } else {
    "无"
  }
}

///|
fn text_format_name(format : @moonpng.TextFormat) -> String {
  match format {
    @moonpng.TextLatin1 => "tEXt"
    @moonpng.TextLatin1Compressed => "zTXt"
    @moonpng.TextInternational => "iTXt"
    @moonpng.TextInternationalCompressed => "iTXt · zlib"
  }
}

///|
fn browser_limits() -> @moonpng.DecodeLimits {
  {
    max_chunk_size: 16 * 1024 * 1024,
    max_chunks: 2048,
    max_compressed_size: 32 * 1024 * 1024,
    max_inflated_size: 64 * 1024 * 1024,
    max_pixels: 16 * 1024 * 1024,
  }
}

///|
fn browser_text_limits() -> @moonpng.TextLimits {
  {
    max_entries: 128,
    max_encoded_bytes: 4 * 1024 * 1024,
    max_decoded_bytes: 8 * 1024 * 1024,
  }
}

///|
fn present_png(name : String, data : Bytes) -> Unit {
  browser_set_busy(true)
  browser_begin_file(name, data.length())
  browser_set_status("working", "正在校验 PNG 结构与校验和…")
  browser_clear_chunks()
  browser_clear_text_entries()
  match @moonpng.inspect(data) {
    Err(error) => {
      browser_set_status("error", "结构校验失败：\{error.message()}")
      browser_set_busy(false)
    }
    Ok(info) => {
      for index, chunk in info.chunks {
        browser_add_chunk(
          index,
          chunk.kind,
          chunk.length,
          chunk.offset,
          chunk.is_critical,
        )
      }
      let text_entries = match
        @moonpng.read_text_entries_with_limits(data, browser_text_limits()) {
        Err(error) => {
          browser_set_status(
            "error",
            "文本元数据校验失败：\{error.message()}",
          )
          browser_set_busy(false)
          return
        }
        Ok(value) => value
      }
      for entry in text_entries {
        browser_add_text_entry(
          text_format_name(entry.format),
          entry.keyword,
          entry.text,
          entry.language_tag,
        )
      }
      browser_set_status("working", "结构有效，正在解码像素…")
      match @moonpng.decode_with_limits(data, browser_limits()) {
        Err(error) => {
          browser_set_status("error", "像素解码失败：\{error.message()}")
          browser_set_busy(false)
        }
        Ok(image) => {
          ignore(browser_draw_rgba(image.width, image.height, image.pixels))
          browser_set_status(
            "working", "解码完成，正在执行往返编码校验…",
          )
          match @moonpng.encode_rgba8(image.width, image.height, image.pixels) {
            Err(error) => {
              browser_set_status(
                "error",
                "重新编码失败：\{error.message()}",
              )
              browser_set_busy(false)
            }
            Ok(encoded) => {
              let encoded = match
                @moonpng.replace_text_entries(encoded, text_entries) {
                Err(error) => {
                  browser_set_status(
                    "error",
                    "文本元数据写入失败：\{error.message()}",
                  )
                  browser_set_busy(false)
                  return
                }
                Ok(value) => value
              }
              match @moonpng.decode_with_limits(encoded, browser_limits()) {
                Err(error) =>
                  browser_set_status(
                    "error",
                    "编码结果无法解码：\{error.message()}",
                  )
                Ok(roundtrip) =>
                  if roundtrip.pixels == image.pixels {
                    browser_present_summary(
                      name,
                      data.length(),
                      info.width,
                      info.height,
                      info.bit_depth,
                      color_format_name(info.color_type),
                      interlace_name(info.interlace_method),
                      image.pixels.length(),
                      encoded.length(),
                      info.chunks.length(),
                      text_entries.length(),
                    )
                    browser_set_download(encoded, name)
                    browser_set_status(
                      "success", "结构、CRC、解码及往返编码校验全部通过。",
                    )
                  } else {
                    browser_set_status(
                      "error", "往返编码后的像素与原图不一致。",
                    )
                  }
              }
              browser_set_busy(false)
            }
          }
        }
      }
    }
  }
}

///|
fn sample_channel(value : Int) -> Byte {
  if value > 255 {
    b'\xff'
  } else {
    value.to_byte()
  }
}

///|
fn sample_png() -> Result[Bytes, @moonpng.EncodeError] {
  let width = 192
  let height = 120
  let pixels : Array[Byte] = []
  pixels.reserve_capacity(width * height * 4)
  for y = 0; y < height; y = y + 1 {
    for x = 0; x < width; x = x + 1 {
      let grid = if (x / 16 + y / 16) % 2 == 0 { 22 } else { 0 }
      pixels.push(sample_channel(x * 215 / (width - 1) + 20 + grid))
      pixels.push(sample_channel(y * 170 / (height - 1) + 48 + grid))
      pixels.push(sample_channel(210 - x * 112 / (width - 1) + grid))
      pixels.push(b'\xff')
    }
  }
  @moonpng.encode_rgba8(
    width.reinterpret_as_uint(),
    height.reinterpret_as_uint(),
    Bytes::from_array(pixels),
  )
}

///|
fn main {
  browser_bind_file_handler(present_png)
  match sample_png() {
    Ok(png) =>
      match
        @moonpng.add_text_entries(png, [
          @moonpng.latin1_text("Software", "MoonPNG"),
          @moonpng.international_text(
            "Title",
            "MoonPNG 浏览器示例",
            language_tag="zh-Hans",
            translated_keyword="标题",
          ),
        ]) {
        Ok(with_text) => present_png("moonpng-sample.png", with_text)
        Err(error) =>
          browser_set_status(
            "error",
            "示例元数据生成失败：\{error.message()}",
          )
      }
    Err(error) =>
      browser_set_status(
        "error",
        "示例图片生成失败：\{error.message()}",
      )
  }
}
