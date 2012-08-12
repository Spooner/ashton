module Ashton
  class Texture
    include Mixins::VersionChecking

    DEFAULT_DRAW_COLOR = Gosu::Color::WHITE
    VALID_DRAW_MODES = [:alpha_blend, :add, :multiply, :replace]

    def rendering?; @rendering end

    # @overload initialize(image)
    # @overload initialize(blob, width, height)
    # @overload initialize(width, height)
    def initialize(*args)
      case args.size
        when 1
          # Create from Gosu::Image
          image = args[0]
          raise TypeError, "Expected Gosu::Image" unless image.is_a? Gosu::Image
          initialize_ image.width, image.height, nil

          render do
            # TODO: Ideally we'd draw the image in replacement mode, but Gosu doesn't support that.
            $window.gl do
              info = image.gl_tex_info
              glEnable GL_TEXTURE_2D
              glBindTexture GL_TEXTURE_2D, info.tex_name
              glEnable GL_BLEND
              glBlendFunc GL_ONE, GL_ZERO

              glBegin GL_QUADS do
                glTexCoord2d info.left, info.bottom
                glVertex2d 0, height # BL

                glTexCoord2d info.left, info.top
                glVertex2d 0, 0 # TL

                glTexCoord2d info.right, info.top
                glVertex2d width, 0 # TR

                glTexCoord2d info.right, info.bottom
                glVertex2d width, height # BR
              end
            end
          end

        when 2
          # Create blank image.
          width, height = *args
          initialize_ width, height, nil
          clear

        when 3
          # Create from blob - create a Gosu image first.
          blob, width, height = *args
          raise ArgumentError, "Blob data is not of expected size" if blob.length != width * height * 4
          initialize_ width, height, blob

        else
          raise ArgumentError, "Expected 1, 2 or 3 parameters."
      end

      @rendering = false
    end

    public
    # Clears the buffer, optionally to a specific color.
    #
    # @option options :color [Gosu::Color, Array<Float>] (transparent)
    def clear(options = {})
      options = {
          color: [0.0, 0.0, 0.0, 0.0],
      }.merge! options

      color = options[:color]
      color = color.to_opengl if color.is_a? Gosu::Color

      glBindFramebufferEXT GL_FRAMEBUFFER_EXT, fbo_id unless rendering?

      glDisable GL_BLEND # Need to replace the alpha too.
      glClearColor *color
      glClear GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT
      glEnable GL_BLEND

      glBindFramebufferEXT GL_FRAMEBUFFER_EXT, 0 unless rendering?

      nil
    end

    public
    # Enable the texture to use (e.g. to draw or convert it).
    def render
      raise ArgumentError, "block required (use #enable/#disable without blocks)" unless block_given?

      enable
      begin
        result = yield self
      ensure
        disable
      end

      result
    end

    public
    def enable
      raise AshtonError if rendering?

      $window.flush # Ensure that any drawing _before_ the render block is drawn to screen, rather than into the buffer.

      enable_

      @rendering = true
    end

    public
    def disable
      raise AshtonError unless rendering?

      $window.flush # Force all the drawing to draw now!
      glBindFramebufferEXT GL_FRAMEBUFFER_EXT, 0

      # Back to Gosu projection.
      glMatrixMode GL_PROJECTION
      glLoadIdentity
      glViewport 0, 0, $window.width, $window.height
      glOrtho 0, $window.width, $window.height, 0, -1, 1

      @rendering = false
    end

    # @!method draw(x, y, z, options = {})
    #   Draw the Texture.
    #
    #   This is not as versatile as converting the Texture into a Gosu::Image and then
    #   drawing it, but it is many times faster, so use it when you are updating the buffer
    #   every frame, rather than just composing an image.
    #
    #   Drawing in Gosu orientation will be flipped in standard OpenGL and visa versa.
    #
    #   @param x [Number] Top left corner x.
    #   @param y [Number] Top left corner y.
    #   @param z [Number] Z-order (can be nil to draw immediately)
    #
    #   @option options :shader [Ashton::Shader] Shader to apply to drawing.
    #   @option options :color [Gosu::Color] (Gosu::Color::WHITE) Color to apply to the drawing.
    #   @option options :mode [Symbol] (:alpha_blend) :alpha_blend, :add, :multiply, :replace
    def draw(x, y, z, options = {})
      shader = options[:shader]
      color = options[:color] || DEFAULT_DRAW_COLOR
      mode = options[:mode] || :alpha_blend

      unless shader.nil? || shader.is_a?(Shader)
        raise TypeError, "Expected :shader option of type Ashton::Shader"
      end

      raise TypeError, "Expected :color option of type Gosu::Color" unless color.is_a? Gosu::Color
      raise TypeError, "Expected :mode option to be a Symbol" unless mode.is_a? Symbol
      raise ArgumentError, "Unsupported draw :mode, #{mode.inspect}" unless VALID_DRAW_MODES.include? mode

      shader.enable z if shader

      $window.gl z do
        if shader
          shader.color = color
          location = shader.send :uniform_location, "in_TextureEnabled", required: false
          shader.send :set_uniform, location, true if location != Shader::INVALID_LOCATION
        else
          glColor4f *color.to_opengl
        end

        glEnable GL_TEXTURE_2D
        glBindTexture GL_TEXTURE_2D, id

        # Set blending mode.
        glEnable GL_BLEND
        case mode
          when :alpha_blend
            glBlendFunc GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
          when :add
            glBlendFunc GL_ONE, GL_ONE
          when :multiply
            glBlendFunc GL_DST_COLOR, GL_ZERO
          when :replace
            glBlendFunc GL_ONE, GL_ZERO
          else
            raise ArgumentError, "Unrecognised draw :mode, #{mode.inspect}"
        end

        glBegin GL_QUADS do
          glTexCoord2d 0, 1
          glMultiTexCoord2d GL_TEXTURE1, 0, 1
          glVertex2d x, y + height # BL

          glTexCoord2d 0, 0
          glMultiTexCoord2d GL_TEXTURE1, 0, 0
          glVertex2d x, y # TL

          glTexCoord2d 1, 0
          glMultiTexCoord2d GL_TEXTURE1, 1, 0
          glVertex2d x + width, y # TR

          glTexCoord2d 1, 1
          glMultiTexCoord2d GL_TEXTURE1, 1, 1
          glVertex2d x + width, y + height # BR
        end
      end

      shader.disable z if shader
    end

    public
    # Convert the current contents of the buffer into a Gosu::Image
    #
    # @option options :caching [Boolean] (true) TexPlay behaviour.
    # @option options :tileable [Boolean] (false) Standard Gosu behaviour.
    # @option options :rect [Array<Integer>] ([0, 0, width, height]) Rectangular area of buffer to use to create the image [x, y, w, h]
    def to_image(*args)
      cache.to_image *args
    end

    def dup
      # Create a new texture and draw self into it.
      new_texture = Texture.new width, height
      new_texture.render do
        draw 0, 0, 0, mode: :replace
      end
      new_texture
    end
  end
end