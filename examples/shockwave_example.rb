# Use of GLSL shader in Gosu to post-process the entire screen.

begin
  require 'rubygems'
rescue LoadError
end

$LOAD_PATH.unshift File.expand_path('../lib/', File.dirname(__FILE__))
require "ashton"

def media_path(file); File.expand_path "media/#{file}", File.dirname(__FILE__) end

class Shockwave
  attr_reader :shader

  def age; (Gosu::milliseconds - @start_time) / 1000.0; end
  def dead?; age > 3.0 end

  def initialize(x, y)
    @shader = Ashton::Shader.new fragment: :shockwave, uniforms: {
        shock_params: [10.0, 0.8, 0.1], # Not entirely sure what these represent!
        center: [x, y],
    }
    @start_time = Gosu::milliseconds
  end

  def update
    @shader.time = age
  end
end

class TestWindow < Gosu::Window
  def initialize
    super 640, 480, false
    self.caption = "Post-processing with 'shockwave2.frag' - Click on window to create a splash!"

    @font = Gosu::Font.new self, Gosu::default_font_name, 40
    @background = Gosu::Image.new(self, media_path("Earth.png"), true)
    @waves = []
  end

  def update
    $gosu_blocks.clear if defined? $gosu_blocks # Workaround for Gosu bug (0.7.45)

    @waves.delete_if {|w| w.dead? }
    @waves.each {|w| w.update }
  end

  def needs_cursor?
    true
  end

  def button_down(id)
    case id
      when Gosu::MsLeft
        @waves << Shockwave.new(mouse_x, mouse_y)
      when Gosu::KbEscape
        close
    end
  end

  def draw
    shaders = @waves.map {|w| w.shader }
    post_process(*shaders) do
      @background.draw 0, 0, 0, width.fdiv(@background.width), height.fdiv(@background.height)
      @font.draw_rel "Hello world!", 350, 50, 0, 0.5, 0.5
      @font.draw_rel "Goodbye world!", 400, 350, 0, 0.5, 0.5
    end

    # Drawing after the effect isn't processed, which is useful for GUI elements.
    @font.draw "FPS: #{Gosu::fps} Waves: #{@waves.size}", 0, 0, 0
  end
end

TestWindow.new.show