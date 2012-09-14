#include "pixel_cache.h"

VALUE rb_cPixelCache;

// Helpers
static void cache_texture(PixelCache* pixel_cache);
static Color_i get_pixel_color(PixelCache* pixel_cache, VALUE x, VALUE y);
static VALUE pixel_cache_allocate(VALUE klass);
static void pixel_cache_mark(PixelCache* pixel_cache);
static void pixel_cache_free(PixelCache* pixel_cache);

void Init_Ashton_PixelCache(VALUE module)
{
    rb_cPixelCache = rb_define_class_under(module, "PixelCache", rb_cObject);

    rb_define_alloc_func(rb_cPixelCache, pixel_cache_allocate);

    rb_define_method(rb_cPixelCache, "initialize", Ashton_PixelCache_init, 1);

    // Getters
    rb_define_method(rb_cPixelCache, "owner", Ashton_PixelCache_get_owner, 0);
    rb_define_method(rb_cPixelCache, "width", Ashton_PixelCache_get_width, 0);
    rb_define_method(rb_cPixelCache, "height", Ashton_PixelCache_get_height, 0);

    // Methods
    rb_define_method(rb_cPixelCache, "[]", Ashton_PixelCache_get_pixel, 2);
    rb_define_method(rb_cPixelCache, "rgba", Ashton_PixelCache_get_rgba_array, 2);
    rb_define_method(rb_cPixelCache, "red", Ashton_PixelCache_get_red, 2);
    rb_define_method(rb_cPixelCache, "green", Ashton_PixelCache_get_green, 2);
    rb_define_method(rb_cPixelCache, "blue", Ashton_PixelCache_get_blue, 2);
    rb_define_method(rb_cPixelCache, "alpha", Ashton_PixelCache_get_alpha, 2);
    rb_define_method(rb_cPixelCache, "transparent?", Ashton_PixelCache_is_transparent, 2);

    rb_define_method(rb_cPixelCache, "refresh", Ashton_PixelCache_refresh, 0);
    rb_define_method(rb_cPixelCache, "to_blob", Ashton_PixelCache_to_blob, 0);
}

//
VALUE Ashton_PixelCache_get_width(VALUE self)
{
    PIXEL_CACHE();
    return UINT2NUM(pixel_cache->width);
}

//
VALUE Ashton_PixelCache_get_height(VALUE self)
{
    PIXEL_CACHE();
    return UINT2NUM(pixel_cache->height);
}


//
static VALUE pixel_cache_allocate(VALUE klass)
{
    PixelCache* pixel_cache = ALLOC(PixelCache);
    memset(pixel_cache, 0, sizeof(PixelCache));

    return Data_Wrap_Struct(klass, pixel_cache_mark, pixel_cache_free, pixel_cache);
}

//
static void pixel_cache_mark(PixelCache* pixel_cache)
{
    rb_gc_mark(pixel_cache->rb_owner);
}

//
static void pixel_cache_free(PixelCache* pixel_cache)
{
    xfree(pixel_cache->data);
    xfree(pixel_cache);
}

//
VALUE Ashton_PixelCache_init(VALUE self, VALUE owner)
{
    PIXEL_CACHE();

    pixel_cache->rb_owner = owner;

    // Different behaviour depending on what the owning class is.
    if(RTEST(rb_obj_is_kind_of(owner, rb_cTexture)))
    {
        // Ashton::Texture
        pixel_cache->texture_id = NUM2UINT(rb_funcall(owner, rb_intern("id"), 0));
    }
    else if(RTEST(rb_obj_is_kind_of(owner, rb_cImage)))
    {
        // Gosu::Image
        // TODO: this needs to be done completely differently, since the image is a sprite on a texture, 1024x1024.
        VALUE tex_info = rb_funcall(owner, rb_intern("gl_tex_info"), 0);
        pixel_cache->texture_id = NUM2UINT(rb_funcall(tex_info, rb_intern("tex_name"), 0));
    }
    else
    {
        rb_raise(rb_eTypeError, "Can only cache Gosu::Image or Ashton::Texture objects.");
    }

    pixel_cache->width = NUM2UINT(rb_funcall(owner, rb_intern("width"), 0));
    pixel_cache->height = NUM2UINT(rb_funcall(owner, rb_intern("height"), 0));
    pixel_cache->data = ALLOC_N(Color_i, pixel_cache->width * pixel_cache->height);
    cache_texture(pixel_cache);

    return Qnil;
}

// Make a copy of the pixel_cache texture in main memory.
static void cache_texture(PixelCache* pixel_cache)
{
    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, pixel_cache->texture_id);
    glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixel_cache->data);

    pixel_cache->is_cached = true;
}

// Get color of a single pixel.
static Color_i get_pixel_color(PixelCache* pixel_cache, VALUE x, VALUE y)
{
    int _x = NUM2INT(x);
    int _y = NUM2INT(y);

    if(_x < 0 || _x >= (int)pixel_cache->width ||
       _y < 0 || _y >= (int)pixel_cache->height)
    {
        Color_i color;
        memset(&color, 0, sizeof(Color_i));
        return color;
    }
    else
    {
        if(!pixel_cache->is_cached) cache_texture(pixel_cache);

        return pixel_cache->data[_x + _y * pixel_cache->width];
    }
}

VALUE Ashton_PixelCache_get_owner(VALUE self)
{
    PIXEL_CACHE();
    return pixel_cache->rb_owner;
}

//
VALUE Ashton_PixelCache_refresh(VALUE self)
{
    PIXEL_CACHE();
    // Lazy refresh - we take a new copy only when we access it next.
    pixel_cache->is_cached = false;
    return Qnil;
}

// Gosu:Color object.
VALUE Ashton_PixelCache_get_pixel(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();

    Color_i rgba = get_pixel_color(pixel_cache, x, y);

    VALUE color = rb_funcall(rb_cColor, rb_intern("new"), 1,
                             UINT2NUM((rgba.alpha << 24) +
                                      (rgba.red   << 16) +
                                      (rgba.green <<  8) +
                                       rgba.blue));

    return color;
}

// RGBA array [255, 255, 255, 255]
VALUE Ashton_PixelCache_get_rgba_array(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();

    Color_i rgba = get_pixel_color(pixel_cache, x, y);

    VALUE array = rb_ary_new();
    rb_ary_push(array, UINT2NUM(rgba.red));
    rb_ary_push(array, UINT2NUM(rgba.green));
    rb_ary_push(array, UINT2NUM(rgba.blue));
    rb_ary_push(array, UINT2NUM(rgba.alpha));

    return array;
}

//
VALUE Ashton_PixelCache_get_red(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();
    Color_i rgba = get_pixel_color(pixel_cache, x, y);
    return UINT2NUM(rgba.red);
}

//
VALUE Ashton_PixelCache_get_green(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();
    Color_i rgba = get_pixel_color(pixel_cache, x, y);
    return UINT2NUM(rgba.green);
}

//
VALUE Ashton_PixelCache_get_blue(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();
    Color_i rgba = get_pixel_color(pixel_cache, x, y);
    return UINT2NUM(rgba.blue);
}

//
VALUE Ashton_PixelCache_get_alpha(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();
    Color_i rgba = get_pixel_color(pixel_cache, x, y);
    return UINT2NUM(rgba.alpha);
}

//
VALUE Ashton_PixelCache_is_transparent(VALUE self, VALUE x, VALUE y)
{
    PIXEL_CACHE();
    Color_i rgba = get_pixel_color(pixel_cache, x, y);
    return (rgba.alpha == 0) ? Qtrue : Qfalse;
}

//
VALUE Ashton_PixelCache_to_blob(VALUE self)
{
   PIXEL_CACHE();

   uint size = sizeof(Color_i) * pixel_cache->width * pixel_cache->height;
   VALUE blob = rb_str_new(NULL, size);

   memcpy(RSTRING_PTR(blob), pixel_cache->data, size);

   return blob;
}