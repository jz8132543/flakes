#define _GNU_SOURCE
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <png.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <systemd/sd-daemon.h>
#include <unistd.h>
#include <wayland-client.h>

#include "color-management-v1-client-protocol.h"
#include "fractional-scale-v1-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

#if !defined(PNG_READ_cICP_SUPPORTED)
#error "libpng with native cICP support is required"
#endif
#if __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "16-bit SHM packing currently requires a little-endian host"
#endif

struct app;
struct output {
    struct app *app;
    struct output *next;
    struct wl_output *object;
    uint32_t id;
    int32_t width, height, scale, transform;
};

struct buffer {
    struct app *app;
    struct buffer *next;
    struct wl_buffer *object;
    void *pixels;
    size_t size;
};

struct app {
    const char *connector;
    struct wl_display *display;
    struct wl_compositor *compositor;
    struct wl_shm *shm;
    struct zwlr_layer_shell_v1 *shell;
    struct wp_viewporter *viewporter;
    struct wp_fractional_scale_manager_v1 *fractional_manager;
    struct wp_color_manager_v1 *color_manager;
    struct wp_image_description_v1 *description;
    struct wp_color_management_surface_v1 *color_surface;
    struct wl_surface *surface;
    struct zwlr_layer_surface_v1 *layer;
    struct wp_viewport *viewport;
    struct output *outputs, *target;
    struct buffer *buffers;
    unsigned buffer_count;
    float *image;
    uint32_t image_width, image_height;
    uint32_t width, height, fractional_scale, format;
    uint32_t last_width, last_height, last_buffer_width, last_buffer_height;
    bool xb48, color_done, parametric, luminances, mastering;
    bool pq, bt2020, perceptual, ready, configured, dirty;
};

static _Noreturn void die(const char *format, ...)
{
    va_list args;
    fputs("hdr-wallpaper: ", stderr);
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    exit(EXIT_FAILURE);
}

static double pq_decode(double code)
{
    const double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 32.0;
    const double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 128.0;
    const double c3 = 2392.0 / 128.0;
    double p = pow(code, 1.0 / m2);
    return 10000.0 * pow(fmax(p - c1, 0.0) / (c2 - c3 * p), 1.0 / m1);
}

static double pq_encode(double nits)
{
    const double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 32.0;
    const double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 128.0;
    const double c3 = 2392.0 / 128.0;
    double p = pow(fmax(nits, 0.0) / 10000.0, m1);
    return pow((c1 + c2 * p) / (1.0 + c3 * p), m2);
}

static void png_fatal(png_structp png, png_const_charp message)
{
    (void)png;
    die("invalid PNG: %s", message);
}

static void read_png(struct app *app, const char *path)
{
    FILE *file = fopen(path, "rb");
    if (!file)
        die("cannot open %s: %s", path, strerror(errno));
    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL,
                                           png_fatal, png_fatal);
    if (!png)
        die("cannot create PNG reader");
    png_infop info = png_create_info_struct(png);
    if (!info)
        die("cannot allocate PNG metadata");
    png_set_crc_action(png, PNG_CRC_ERROR_QUIT, PNG_CRC_ERROR_QUIT);
    png_set_user_limits(png, 32768, 32768);
    png_init_io(png, file);
    png_read_info(png, info);
    app->image_width = png_get_image_width(png, info);
    app->image_height = png_get_image_height(png, info);
    png_byte primaries, tf, matrix, full_range;
    if (png_get_bit_depth(png, info) != 16 ||
        png_get_color_type(png, info) != PNG_COLOR_TYPE_RGB ||
        png_get_valid(png, info, PNG_INFO_tRNS))
        die("PNG must be opaque 16-bit RGB, without alpha or tRNS");
    if (!png_get_cICP(png, info, &primaries, &tf, &matrix, &full_range) ||
        primaries != 9 || tf != 16 || matrix != 0 || full_range != 1)
        die("PNG must contain cICP=9,16,0,1 (full-range BT.2020 PQ RGB)");
    size_t count = (size_t)app->image_width * app->image_height;
    if (!count || count > 64 * 1024 * 1024)
        die("PNG exceeds the 64 megapixel limit");
    png_set_interlace_handling(png);
    png_read_update_info(png, info);
    size_t stride = (size_t)app->image_width * 6;
    if (png_get_rowbytes(png, info) != stride)
        die("unexpected 16-bit RGB PNG row size");
    png_bytep raw = malloc(count * 6);
    png_bytepp rows = malloc((size_t)app->image_height * sizeof(*rows));
    app->image = malloc(count * 3 * sizeof(*app->image));
    float *lut = malloc(65536 * sizeof(*lut));
    if (!raw || !rows || !app->image || !lut)
        die("cannot allocate PNG pixels");
    for (uint32_t y = 0; y < app->image_height; ++y)
        rows[y] = raw + (size_t)y * stride;
    png_read_image(png, rows);
    png_read_end(png, info);
    png_destroy_read_struct(&png, &info, NULL);
    fclose(file);
    for (unsigned i = 0; i < 65536; ++i)
        lut[i] = (float)pq_decode(i / 65535.0);
    for (size_t i = 0; i < count * 3; ++i) {
        /* libpng's untransformed 16-bit samples are in network byte order. */
        unsigned sample = ((unsigned)raw[i * 2] << 8) | raw[i * 2 + 1];
        if (lut[sample] > 480.1f)
            die("PNG channel exceeds the 480-nit mastering volume");
        app->image[i] = fminf(lut[sample], 480.0f);
    }
    free(lut);
    free(rows);
    free(raw);
}

static uint64_t pack_pixel(const double rgb[3], uint32_t x, uint32_t y)
{
    uint32_t q[3];
    uint32_t maximum = (uint32_t)floor(pq_encode(480.0) * 65535.0);
    for (unsigned c = 0; c < 3; ++c) {
        uint32_t hash = x * 0x9e3779b9u ^ y * 0x85ebca6bu ^ c * 0xc2b2ae35u;
        hash ^= hash >> 16;
        hash *= 0x7feb352du;
        hash ^= hash >> 15;
        hash *= 0x846ca68bu;
        hash ^= hash >> 16;
        double noise = (hash & 65535) / 65535.0 - 0.5;
        double code = floor(pq_encode(rgb[c]) * 65535.0 + 0.5 + noise);
        q[c] = (uint32_t)fmax(0.0, fmin(code, maximum));
    }
    return UINT64_C(0xffff000000000000) | ((uint64_t)q[2] << 32) |
           ((uint64_t)q[1] << 16) | q[0];
}

static void buffer_release(void *data, struct wl_buffer *object)
{
    struct buffer *buffer = data;
    struct buffer **link = &buffer->app->buffers;
    while (*link != buffer)
        link = &(*link)->next;
    *link = buffer->next;
    --buffer->app->buffer_count;
    wl_buffer_destroy(object);
    munmap(buffer->pixels, buffer->size);
    free(buffer);
}

static const struct wl_buffer_listener buffer_listener = {
    .release = buffer_release,
};

static void render(struct app *app)
{
    if (!app->ready || !app->configured || !app->dirty || app->buffer_count >= 3)
        return;
    struct output *output = app->target;
    uint32_t bw = output->width, bh = output->height;
    bool rotated = output->transform == WL_OUTPUT_TRANSFORM_90 ||
                   output->transform == WL_OUTPUT_TRANSFORM_270 ||
                   output->transform == WL_OUTPUT_TRANSFORM_FLIPPED_90 ||
                   output->transform == WL_OUTPUT_TRANSFORM_FLIPPED_270;
    if (rotated) {
        uint32_t swap = bw;
        bw = bh;
        bh = swap;
    }
    double scale = app->fractional_scale ? app->fractional_scale / 120.0 :
                                          output->scale;
    uint32_t width = app->width, height = app->height;
    if (!width && bw)
        width = (uint32_t)fmax(1.0, round(bw / scale));
    if (!height && bh)
        height = (uint32_t)fmax(1.0, round(bh / scale));
    if (!bw && width)
        bw = (uint32_t)ceil(width * scale);
    if (!bh && height)
        bh = (uint32_t)ceil(height * scale);
    if (!width || !height || !bw || !bh || width > INT32_MAX ||
        height > INT32_MAX || bw > 32768 || bh > 32768 ||
        (uint64_t)bw * bh > 64 * 1024 * 1024)
        die("invalid output/configure dimensions");
    app->dirty = false;
    if (width == app->last_width && height == app->last_height &&
        bw == app->last_buffer_width && bh == app->last_buffer_height)
        return;

    struct buffer *buffer = calloc(1, sizeof(*buffer));
    if (!buffer)
        die("cannot allocate SHM buffer");
    buffer->app = app;
    buffer->size = (size_t)bw * bh * 8;
    int fd = memfd_create("hdr-wallpaper", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (fd < 0 || ftruncate(fd, (off_t)buffer->size) < 0)
        die("cannot create SHM storage: %s", strerror(errno));
    buffer->pixels = mmap(NULL, buffer->size, PROT_READ | PROT_WRITE,
                          MAP_SHARED, fd, 0);
    if (buffer->pixels == MAP_FAILED)
        die("cannot map SHM storage: %s", strerror(errno));

    /* Centered cover, interpolated in absolute linear light, not PQ code space. */
    double step = fmin(app->image_width / (double)bw,
                       app->image_height / (double)bh);
    double left = (app->image_width - bw * step) * 0.5;
    double top = (app->image_height - bh * step) * 0.5;
    uint64_t *pixels = buffer->pixels;
    for (uint32_t y = 0; y < bh; ++y) {
        double sy = fmax(0.0, fmin(top + (y + 0.5) * step - 0.5,
                                  app->image_height - 1.0));
        uint32_t y0 = (uint32_t)sy;
        uint32_t y1 = y0 + (y0 + 1 < app->image_height);
        double fy = sy - y0;
        for (uint32_t x = 0; x < bw; ++x) {
            double sx = fmax(0.0, fmin(left + (x + 0.5) * step - 0.5,
                                      app->image_width - 1.0));
            uint32_t x0 = (uint32_t)sx;
            uint32_t x1 = x0 + (x0 + 1 < app->image_width);
            double fx = sx - x0, rgb[3];
            for (unsigned c = 0; c < 3; ++c) {
                double a = app->image[((size_t)y0 * app->image_width + x0) * 3 + c];
                double b = app->image[((size_t)y0 * app->image_width + x1) * 3 + c];
                double d = app->image[((size_t)y1 * app->image_width + x0) * 3 + c];
                double e = app->image[((size_t)y1 * app->image_width + x1) * 3 + c];
                rgb[c] = (a + (b - a) * fx) * (1.0 - fy) +
                         (d + (e - d) * fx) * fy;
            }
            pixels[(size_t)y * bw + x] = pack_pixel(rgb, x, y);
        }
    }
    struct wl_shm_pool *pool = wl_shm_create_pool(app->shm, fd, buffer->size);
    if (!pool)
        die("cannot create Wayland SHM pool");
    buffer->object = wl_shm_pool_create_buffer(pool, 0, bw, bh, bw * 8,
                                               app->format);
    wl_shm_pool_destroy(pool);
    close(fd);
    if (!buffer->object || wl_buffer_add_listener(buffer->object, &buffer_listener,
                                                 buffer) < 0)
        die("cannot create Wayland SHM buffer");
    buffer->next = app->buffers;
    app->buffers = buffer;
    ++app->buffer_count;
    wp_viewport_set_destination(app->viewport, width, height);
    wl_surface_set_buffer_scale(app->surface, 1);
    /* This description and the first buffer become current in the same commit. */
    wp_color_management_surface_v1_set_image_description(app->color_surface,
        app->description, WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL);
    wl_surface_attach(app->surface, buffer->object, 0, 0);
    wl_surface_damage_buffer(app->surface, 0, 0, bw, bh);
    wl_surface_commit(app->surface);
    bool first_frame = !app->last_width;
    if (first_frame)
        fprintf(stderr, "hdr-wallpaper: %s, %ux%u buffer -> %ux%u logical, XB48, "
                         "BT.2020 PQ, reference 203 nits, mastering 480 nits\n",
                app->connector, bw, bh, width, height);
    app->last_width = width;
    app->last_height = height;
    app->last_buffer_width = bw;
    app->last_buffer_height = bh;
    if (first_frame) {
        if (wl_display_roundtrip(app->display) < 0)
            die("Wayland rejected the first HDR background commit");
        if (sd_notify(0, "READY=1") < 0)
            die("cannot notify the service manager that the background is ready");
    }
}

static void output_geometry(void *data, struct wl_output *object, int32_t x,
                            int32_t y, int32_t pw, int32_t ph, int32_t subpixel,
                            const char *make, const char *model, int32_t transform)
{
    (void)object; (void)x; (void)y; (void)pw; (void)ph;
    (void)subpixel; (void)make; (void)model;
    struct output *output = data;
    if (transform < WL_OUTPUT_TRANSFORM_NORMAL ||
        transform > WL_OUTPUT_TRANSFORM_FLIPPED_270)
        die("unsupported output transform");
    output->transform = transform;
}

static void output_mode(void *data, struct wl_output *object, uint32_t flags,
                        int32_t width, int32_t height, int32_t refresh)
{
    (void)object; (void)refresh;
    struct output *output = data;
    if (flags & WL_OUTPUT_MODE_CURRENT) {
        if (width <= 0 || height <= 0 || width > 32768 || height > 32768)
            die("invalid current output mode");
        output->width = width;
        output->height = height;
    }
}

static void output_done(void *data, struct wl_output *object)
{
    (void)object;
    struct output *output = data;
    if (output == output->app->target)
        output->app->dirty = true;
}

static void output_scale(void *data, struct wl_output *object, int32_t scale)
{
    (void)object;
    if (scale < 1 || scale > 32)
        die("invalid output scale");
    ((struct output *)data)->scale = scale;
}

static void output_name(void *data, struct wl_output *object, const char *name)
{
    (void)object;
    struct output *output = data;
    if (strcmp(name, output->app->connector) == 0) {
        if (output->app->target && output->app->target != output)
            die("ambiguous output connector: %s", name);
        output->app->target = output;
    }
}

static void output_description(void *data, struct wl_output *object,
                               const char *description)
{
    (void)data; (void)object; (void)description;
}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

static void shm_format(void *data, struct wl_shm *shm, uint32_t format)
{
    (void)shm;
    struct app *app = data;
    if (format == WL_SHM_FORMAT_XBGR16161616)
        app->xb48 = true;
}

static const struct wl_shm_listener shm_listener = { .format = shm_format };

static void color_intent(void *data, struct wp_color_manager_v1 *manager,
                         uint32_t intent)
{
    (void)manager;
    if (intent == WP_COLOR_MANAGER_V1_RENDER_INTENT_PERCEPTUAL)
        ((struct app *)data)->perceptual = true;
}

static void color_feature(void *data, struct wp_color_manager_v1 *manager,
                          uint32_t feature)
{
    (void)manager;
    struct app *app = data;
    switch (feature) {
    case WP_COLOR_MANAGER_V1_FEATURE_PARAMETRIC: app->parametric = true; break;
    case WP_COLOR_MANAGER_V1_FEATURE_SET_LUMINANCES: app->luminances = true; break;
    case WP_COLOR_MANAGER_V1_FEATURE_SET_MASTERING_DISPLAY_PRIMARIES:
        app->mastering = true; break;
    default: break;
    }
}

static void color_tf(void *data, struct wp_color_manager_v1 *manager, uint32_t tf)
{
    (void)manager;
    if (tf == WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ)
        ((struct app *)data)->pq = true;
}

static void color_primaries(void *data, struct wp_color_manager_v1 *manager,
                            uint32_t primaries)
{
    (void)manager;
    if (primaries == WP_COLOR_MANAGER_V1_PRIMARIES_BT2020)
        ((struct app *)data)->bt2020 = true;
}

static void color_done(void *data, struct wp_color_manager_v1 *manager)
{
    (void)manager;
    ((struct app *)data)->color_done = true;
}

static const struct wp_color_manager_v1_listener color_listener = {
    .supported_intent = color_intent,
    .supported_feature = color_feature,
    .supported_tf_named = color_tf,
    .supported_primaries_named = color_primaries,
    .done = color_done,
};

static void description_failed(void *data, struct wp_image_description_v1 *object,
                               uint32_t cause, const char *message)
{
    (void)data; (void)object;
    die("HDR image description failed (%u): %s; refusing SDR fallback",
        cause, message);
}

static void description_ready(void *data, struct wp_image_description_v1 *object,
                              uint32_t identity)
{
    (void)object; (void)identity;
    ((struct app *)data)->ready = true;
}

static void description_ready2(void *data, struct wp_image_description_v1 *object,
                               uint32_t high, uint32_t low)
{
    (void)high;
    description_ready(data, object, low);
}

static const struct wp_image_description_v1_listener description_listener = {
    .failed = description_failed,
    .ready = description_ready,
    .ready2 = description_ready2,
};

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *layer,
                            uint32_t serial, uint32_t width, uint32_t height)
{
    struct app *app = data;
    zwlr_layer_surface_v1_ack_configure(layer, serial);
    app->width = width;
    app->height = height;
    app->configured = true;
    app->dirty = true;
}

static void layer_closed(void *data, struct zwlr_layer_surface_v1 *layer)
{
    (void)data; (void)layer;
    die("background surface closed (output may have been removed)");
}

static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = layer_configure,
    .closed = layer_closed,
};

static void fractional_scale(void *data, struct wp_fractional_scale_v1 *object,
                             uint32_t scale)
{
    (void)object;
    if (!scale || scale > 32 * 120)
        die("invalid fractional scale");
    struct app *app = data;
    app->fractional_scale = scale;
    app->dirty = true;
}

static const struct wp_fractional_scale_v1_listener fractional_listener = {
    .preferred_scale = fractional_scale,
};

static void registry_global(void *data, struct wl_registry *registry, uint32_t id,
                            const char *interface, uint32_t version)
{
    struct app *app = data;
    if (strcmp(interface, wl_compositor_interface.name) == 0 && version >= 4) {
        app->compositor = wl_registry_bind(registry, id, &wl_compositor_interface, 4);
    } else if (strcmp(interface, wl_shm_interface.name) == 0) {
        app->shm = wl_registry_bind(registry, id, &wl_shm_interface, 1);
        if (!app->shm || wl_shm_add_listener(app->shm, &shm_listener, app) < 0)
            die("cannot bind Wayland SHM");
    } else if (strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
        app->shell = wl_registry_bind(registry, id, &zwlr_layer_shell_v1_interface,
                                     version < 4 ? version : 4);
    } else if (strcmp(interface, wp_viewporter_interface.name) == 0) {
        app->viewporter = wl_registry_bind(registry, id, &wp_viewporter_interface, 1);
    } else if (strcmp(interface, wp_fractional_scale_manager_v1_interface.name) == 0) {
        app->fractional_manager = wl_registry_bind(registry, id,
            &wp_fractional_scale_manager_v1_interface, 1);
    } else if (strcmp(interface, wp_color_manager_v1_interface.name) == 0) {
        app->color_manager = wl_registry_bind(registry, id, &wp_color_manager_v1_interface,
                                             version < 3 ? version : 3);
        if (!app->color_manager || wp_color_manager_v1_add_listener(app->color_manager,
            &color_listener, app) < 0)
            die("cannot bind Wayland color management");
    } else if (strcmp(interface, wl_output_interface.name) == 0 && version >= 4) {
        struct output *output = calloc(1, sizeof(*output));
        if (!output)
            die("cannot allocate output");
        output->app = app;
        output->id = id;
        output->scale = 1;
        output->object = wl_registry_bind(registry, id, &wl_output_interface, 4);
        output->next = app->outputs;
        app->outputs = output;
        if (!output->object || wl_output_add_listener(output->object,
            &output_listener, output) < 0)
            die("cannot bind Wayland output");
    }
}

static void registry_remove(void *data, struct wl_registry *registry, uint32_t id)
{
    (void)registry;
    struct app *app = data;
    struct output **link = &app->outputs;
    while (*link && (*link)->id != id)
        link = &(*link)->next;
    if (*link) {
        struct output *output = *link;
        if (output == app->target)
            die("target output %s was removed", app->connector);
        *link = output->next;
        wl_output_release(output->object);
        free(output);
    }
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_remove,
};

#ifdef HDR_WALLPAPER_TEST
#include <assert.h>
#include <sys/wait.h>

static void self_test(void)
{
    for (unsigned i = 1; i <= 65535; ++i)
        assert(fabs(pq_encode(pq_decode(i / 65535.0)) - i / 65535.0) < 1e-10);
    assert(pq_decode(0.0) == 0.0);
    assert(fabs(pq_decode(1.0) - 10000.0) < 1e-8);
    assert(fabs(pq_encode(203.0) - 0.580688881) < 1e-8);
    double red[3] = {203.0, 0.0, 0.0};
    uint64_t packed = pack_pixel(red, 11, 23);
    assert((packed & 65535) > 32767);
    assert(((packed >> 16) & UINT64_C(0xffffffff)) == 0);
    assert((packed >> 48) == 65535);
    assert(packed == pack_pixel(red, 11, 23));
    double blue[3] = {0.0, 0.0, 203.0};
    assert(((pack_pixel(blue, 11, 23) >> 32) & 65535) > 32767);
    assert((pack_pixel(blue, 11, 23) & UINT64_C(0xffffffff)) == 0);
    double peak[3] = {480.0, 480.0, 480.0};
    assert(pq_decode((pack_pixel(peak, 0, 0) & 65535) / 65535.0) <= 480.0);
    for (unsigned test = 0; test < 5; ++test) {
        FILE *file = tmpfile();
        assert(file);
        png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL,
                                                 png_fatal, png_fatal);
        png_infop info = png_create_info_struct(png);
        assert(png && info);
        png_init_io(png, file);
        png_set_IHDR(png, info, 1, 1, test == 2 ? 8 : 16, PNG_COLOR_TYPE_RGB,
                     PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
                     PNG_FILTER_TYPE_DEFAULT);
        if (test != 1)
            png_set_cICP(png, info, 9, test == 3 ? 13 : 16, 0, 1);
        png_write_info(png, info);
        unsigned sample = (unsigned)round(pq_encode(test == 4 ? 600.0 : 203.0) * 65535);
        png_byte row[6] = {sample >> 8, sample & 255, 0, 0, 0, 0};
        png_write_row(png, row);
        png_write_end(png, info);
        png_destroy_write_struct(&png, &info);
        assert(fflush(file) == 0);
        char path[64];
        snprintf(path, sizeof(path), "/proc/self/fd/%d", fileno(file));
        if (test == 0) {
            struct app app = {0};
            read_png(&app, path);
            assert(app.image_width == 1 && app.image_height == 1);
            assert(fabs(app.image[0] - 203.0) < 0.02);
            assert(app.image[1] == 0.0f && app.image[2] == 0.0f);
            free(app.image);
        } else {
            pid_t pid = fork();
            assert(pid >= 0);
            if (pid == 0) {
                struct app app = {0};
                read_png(&app, path);
                _exit(0);
            }
            int status;
            assert(waitpid(pid, &status, 0) == pid);
            assert(WIFEXITED(status) && WEXITSTATUS(status) == EXIT_FAILURE);
        }
        fclose(file);
    }
    puts("HDR offline tests passed: PQ, XB48 channels, dithering, PNG depth/cICP/peak");
}
#endif

int main(int argc, char **argv)
{
#ifdef HDR_WALLPAPER_TEST
    self_test();
    return EXIT_SUCCESS;
#endif
    if (argc != 3 || !argv[1][0])
        die("usage: hdr-wallpaper <output-connector> <16-bit-BT2020-PQ.png>");
    struct app app = { .connector = argv[1] };
    read_png(&app, argv[2]);
    app.display = wl_display_connect(NULL);
    if (!app.display)
        die("cannot connect to Wayland: %s", strerror(errno));
    struct wl_registry *registry = wl_display_get_registry(app.display);
    if (!registry || wl_registry_add_listener(registry, &registry_listener, &app) < 0 ||
        wl_display_roundtrip(app.display) < 0 || wl_display_roundtrip(app.display) < 0)
        die("Wayland registry discovery failed");
    if (!app.compositor || !app.shm || !app.shell || !app.viewporter)
        die("requires compositor v4, wl_shm, layer-shell and viewporter");
    if (!app.target)
        die("output %s not found (wl_output v4 name is required)", app.connector);
    /* Avoid the compositor's unsized GLES packed-10-bit texture upload path. */
    if (!app.xb48)
        die("compositor does not advertise XB48 SHM; refusing SDR fallback");
    app.format = WL_SHM_FORMAT_XBGR16161616;
    if (!app.color_manager || !app.color_done || !app.parametric || !app.luminances ||
        !app.mastering || !app.pq || !app.bt2020 || !app.perceptual)
        die("required PQ/BT.2020 parametric HDR capabilities missing; refusing SDR fallback");
    struct wp_image_description_creator_params_v1 *params =
        wp_color_manager_v1_create_parametric_creator(app.color_manager);
    if (!params)
        die("cannot create HDR image description parameters");
    wp_image_description_creator_params_v1_set_primaries_named(params,
        WP_COLOR_MANAGER_V1_PRIMARIES_BT2020);
    wp_image_description_creator_params_v1_set_tf_named(params,
        WP_COLOR_MANAGER_V1_TRANSFER_FUNCTION_ST2084_PQ);
    wp_image_description_creator_params_v1_set_luminances(params, 0, 10000, 203);
    wp_image_description_creator_params_v1_set_mastering_luminance(params, 0, 480);
    wp_image_description_creator_params_v1_set_max_cll(params, 480);
    app.description = wp_image_description_creator_params_v1_create(params);
    if (!app.description || wp_image_description_v1_add_listener(app.description,
        &description_listener, &app) < 0)
        die("cannot create HDR image description");
    while (!app.ready)
        if (wl_display_dispatch(app.display) < 0)
            die("Wayland disconnected before HDR image description became ready");

    app.surface = wl_compositor_create_surface(app.compositor);
    if (!app.surface)
        die("cannot create background surface");
    app.color_surface = wp_color_manager_v1_get_surface(app.color_manager, app.surface);
    app.viewport = wp_viewporter_get_viewport(app.viewporter, app.surface);
    app.layer = zwlr_layer_shell_v1_get_layer_surface(app.shell, app.surface,
        app.target->object, ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND, "hdr-wallpaper");
    if (!app.color_surface || !app.viewport || !app.layer ||
        zwlr_layer_surface_v1_add_listener(app.layer, &layer_listener, &app) < 0)
        die("cannot create HDR background layer");
    if (app.fractional_manager) {
        struct wp_fractional_scale_v1 *fractional =
            wp_fractional_scale_manager_v1_get_fractional_scale(app.fractional_manager,
                                                                app.surface);
        if (!fractional || wp_fractional_scale_v1_add_listener(fractional,
            &fractional_listener, &app) < 0)
            die("cannot obtain fractional scale");
    }
    zwlr_layer_surface_v1_set_size(app.layer, 0, 0);
    zwlr_layer_surface_v1_set_anchor(app.layer,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
        ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(app.layer, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(app.layer,
        ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);
    struct wl_region *empty = wl_compositor_create_region(app.compositor);
    if (!empty)
        die("cannot create empty input region");
    wl_surface_set_input_region(app.surface, empty);
    wl_region_destroy(empty);
    wl_surface_commit(app.surface);
    while (wl_display_dispatch(app.display) >= 0)
        render(&app);
    die("Wayland connection failed: %s", strerror(errno));
}
