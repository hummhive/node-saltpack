# This class prettifies the output of our armoring stream, according to the saltpack spec.
# At the moment, per the spec, it simply frames the message, and inserts a space every 15 characters
# and a newline every 200 words.

stream = require('keybase-chunk-stream')
util = require('./util')

# Punctuation - this is modular
space = new Buffer(' ')
newline = new Buffer('\n')
punctuation = new Buffer('.')

words_per_line = 200
chars_per_word = 15

# For working with the chunk streams
noop = () ->

# This stream takes basex'd input and writes framed output, as per https://saltpack.org/armoring#framing-the-basex-payload
exports.FormatStream = class FormatStream extends stream.ChunkStream

  # _format is the transform function passed to the chunk stream constructor
  _format : (chunk) ->
    # this branch is only reached during the super's flush()
    if chunk.length < chars_per_word
      return chunk
    else
      results = []
      # insert spaces and newlines where appropriate
      for i in [0...chunk.length] by chars_per_word
        word = chunk[i...i+chars_per_word]
        if i+chars_per_word >= chunk.length
          results.push(word)
        else
          if @_word_count % words_per_line is 0 and @_word_count isnt 0
            word = Buffer.concat([word, newline])
          else
            word = Buffer.concat([word, space])
          ++@_word_count
          results.push(word)
      return Buffer.concat(results)

  _transform : (chunk, encoding, cb) ->
    if not @_header_written
      @push(Buffer.concat([@_header, punctuation, space]))
      @_header_written = true
    super(chunk, encoding, cb)

  _flush : (cb) ->
    super(noop)
    @push(Buffer.concat([punctuation, space, @_footer, punctuation]))
    cb()

  constructor : (opts) ->
    if opts?.brand? then _brand = opts.brand else _brand = 'KEYBASE'
    @_header = new Buffer("BEGIN#{space}#{_brand}#{space}SALTPACK#{space}ENCRYPTED#{space}MESSAGE")
    @_footer = new Buffer("END#{space}#{_brand}#{space}SALTPACK#{space}ENCRYPTED#{space}MESSAGE")
    @_header_written = false
    @_word_count = 0
    super(@_format, {block_size : 1, exact_chunking : false, writableObjectMode : false, readableObjectMode : false})

exports.DeformatStream = class DeformatStream extends stream.ChunkStream

  _header_mode = 0
  _body_mode = 1
  _footer_mode = 2
  _strip_chars = new Buffer('>\n\r\t ')
  _strip_re = /[>\n\r\t ]/g

  _strip = (chunk) -> chunk = chunk.toString().replace(_strip_re, "")

  _deformat : (chunk) ->
   if @_mode is _header_mode
      index = chunk.indexOf(punctuation[0])
      if index isnt -1
        # we found the period
        read_header = chunk[0...index]
        re = /[>\n\r\t ]*BEGIN[>\n\r\t ]+([a-zA-Z0-9]+)?[>\n\r\t ]+SALTPACK[>\n\r\t ]+(ENCRYPTED[>\n\r\t ]+MESSAGE)|(SIGNED[>\n\r\t ]+MESSAGE)|(DETACHED[>\n\r\t ]+SIGNATURE)[>\n\r\t ]*/m
        unless re.test(read_header) then throw new Error("Header failed to verify!")
        @_mode = _body_mode
        @block_size = 1
        @exact_chunking = false
        @extra = chunk[index+punctuation.length+space.length...]
        return new Buffer('')
      else
        # something horrible happened
        throw new Error('Somehow didn\'t get a full header packet')

    else if @_mode is _body_mode
      index = chunk.indexOf(punctuation[0])
      if index is -1
        # we're just in a normal body chunk
        # everything is fine
        return _strip(chunk)
      else
        # we found the end!
        ret = _strip(chunk[...index])
        # put any partial footer into extra
        @extra = chunk[index+punctuation.length+space.length...]
        @block_size = @_footer.length
        @exact_chunking = true
        @_mode = _footer_mode
        return ret

    else if @_mode is _footer_mode
      read_footer = _strip(chunk)
      unless util.bufeq_secure(read_footer, _strip(@_footer)) then throw new Error("Footer failed to verify!")
      # so that we can't enter this statement more than once
      @_mode = -1
    else
      # something very bad happened
      throw new Error("Modes were off, somehow. SAD!")

  # we should never have anything to flush
  _flush : (cb) ->
    cb()

  constructor : (opts) ->
    if opts?.brand? then _brand = opts.brand else _brand = 'KEYBASE'
    @_header = new Buffer("BEGIN#{space}#{_brand}#{space}SALTPACK#{space}ENCRYPTED#{space}MESSAGE")
    @_footer = new Buffer("END#{space}#{_brand}#{space}SALTPACK#{space}ENCRYPTED#{space}MESSAGE")
    @_mode = _header_mode
    super(@_deformat, {block_size : (@_header.length + punctuation.length + space.length), exact_chunking : true, writableObjectMode : false, readableObjectMode : false})
