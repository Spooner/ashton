# Use of GLSL shader in Gosu.

begin
  require 'rubygems'
rescue LoadError
end

$LOAD_PATH.unshift File.expand_path('../lib/', File.dirname(__FILE__))
require "ashton"

def media_path(file); File.expand_path "media/#{file}", File.dirname(__FILE__) end
def output_path(file); File.expand_path "output/#{file}", File.dirname(__FILE__) end

class GameWindow < Gosu::Window
  def initialize
    super 640, 480, false
    self.caption = "Gosu & OpenGL Integration Demo (SHADERS)"

    @font = Gosu::Font.new self, Gosu::default_font_name, 24
    @image = Gosu::Image.new self, media_path("Earth.png"), true

    @sepia = Ashton::Shader.new fragment: :sepia
    @contrast = Ashton::Shader.new fragment: :contrast
    @mezzotint = Ashton::Shader.new fragment: :mezzotint
    @grayscale = Ashton::Shader.new fragment: :grayscale
    @color_inversion = Ashton::Shader.new fragment: :color_inversion
    @fade = Ashton::Shader.new fragment: :fade, uniforms: {
        fade: 0.75,
    }

    update # Ensure values are set before draw.
  end

  def update
    $gosu_blocks.clear if defined? $gosu_blocks # workaround for Gosu 0.7.45 bug.

    @fade.fade = @fade_fade = Math::sin(Gosu::milliseconds / 1000.0) / 2 + 0.5
    @contrast.contrast = @contrast_contrast = Math::sin(Gosu::milliseconds / 1000.0) * 2 + 2
    @mezzotint.t = (Gosu::milliseconds / 100.0).to_i
  end

  def draw
    @image.draw 0, 0, 0, width.fdiv(@image.width), height.fdiv(@image.height)

    # draw, with and without colour.
    @image.draw 10, 10, 0, :shader => @sepia
    @font.draw ":sepia", 10, 150, 0

    @image.draw 10, @image.height + 120, 0, 1, 1, Gosu::Color::RED, :shader => @mezzotint
    @font.draw ":mezzotint", 10, 400, 0

    # draw_rot, with and without colour.
    @image.draw_rot 235, 0, 0, 10, 0, 0, :shader => @contrast
    @font.draw ":contrast #{"%.2f" % @contrast_contrast}", 235, 150, 0

    @image.draw_rot 235, @image.height + 110, 0, 10, 0, 0, 1, 1, Gosu::Color::RED, :shader => @fade
    @font.draw ":fade #{"%.2f" % @fade_fade}", 235, 400, 0

    # More draws.
    @image.draw 430, 10, 0, :shader => @grayscale
    @font.draw ":grayscale", 430, 150, 0

    @image.draw 430, @image.height + 110, 0, :shader => @color_inversion
    @font.draw ":color_inversion", 430, 400, 0
  end

  def button_down(id)
    if id == Gosu::KbEscape
      close
    end
  end
end

window = GameWindow.new
window.show