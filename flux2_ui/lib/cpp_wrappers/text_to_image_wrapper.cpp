#include <cstdint>

#include "flux.h"

#define EXPORT extern "C" __attribute__((visibility("default"))) __attribute__((used))

typedef struct {
	int width;
	int height;
	int num_steps;
	int64_t seed;
	int use_mmap;
	int release_text_encoder;
} flux2_params;

static flux_params flux2_to_flux_params(const flux2_params *params) {
	flux_params out = FLUX_PARAMS_DEFAULT;
	if (!params) {
		return out;
	}
	if (params->width > 0) {
		out.width = params->width;
	}
	if (params->height > 0) {
		out.height = params->height;
	}
	if (params->num_steps > 0) {
		out.num_steps = params->num_steps;
	}
	out.seed = params->seed;
	return out;
}

EXPORT flux_ctx *flux2_load_model(const char *model_dir, const flux2_params *params) {
	if (!model_dir || model_dir[0] == '\0') {
		return NULL;
	}
	flux_ctx *ctx = flux_load_dir(model_dir);
	if (!ctx) {
		return NULL;
	}
	if (params) {
		flux_set_mmap(ctx, params->use_mmap ? 1 : 0);
	}
	return ctx;
}

EXPORT void flux2_free_model(flux_ctx *ctx) {
	if (ctx) {
		flux_free(ctx);
	}
}

EXPORT const char *flux2_last_error(void) {
	return flux_get_error();
}

EXPORT int flux2_generate_to_file(
	flux_ctx *ctx,
	const char *prompt,
	const char *output_path,
	const flux2_params *params
) {
	if (!ctx || !prompt || prompt[0] == '\0' || !output_path || output_path[0] == '\0') {
		return -1;
	}

	flux_params fluxParams = flux2_to_flux_params(params);
	if (params) {
		flux_set_mmap(ctx, params->use_mmap ? 1 : 0);
	}

	flux_image *img = flux_generate(ctx, prompt, &fluxParams);
	if (!img) {
		return -2;
	}

	int save_result = flux_image_save_with_seed(img, output_path, fluxParams.seed);
	flux_image_free(img);

	if (params && params->release_text_encoder) {
		flux_release_text_encoder(ctx);
	}

	return save_result == 0 ? 0 : -3;
}

EXPORT int flux2_generate_to_file_with_model(
	const char *model_dir,
	const char *prompt,
	const char *output_path,
	const flux2_params *params
) {
	if (!model_dir || model_dir[0] == '\0') {
		return -1;
	}
	flux_ctx *ctx = flux2_load_model(model_dir, params);
	if (!ctx) {
		return -2;
	}
	int result = flux2_generate_to_file(ctx, prompt, output_path, params);
	flux2_free_model(ctx);
	return result;
}