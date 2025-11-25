// SPDX-License-Identifier: GPL-2.0
/*
 * Sony IMX662 CMOS Image Sensor Driver
 *
 * The IMX662 is the successor of IMX290/327/462, 1920x1080 1/2.8 CMOS image sensors.
 *
 * Copyright (C) 2022 Soho Enterprise Ltd.
 * Author: Tetsuya Nomura <tetsuya.nomura@soho-enterprise.com>
 *
 * Based on IMX290 driver
 * Copyright (C) 2019 FRAMOS GmbH.
 * and
 * Copyright (C) 2019 Linaro Ltd.
 * Author: Manivannan Sadhasivam <manivannan.sadhasivam@linaro.org>
 *
 */

#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of_device.h>
#include <linux/property.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
#include <linux/regulator/consumer.h>
#include <media/media-entity.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-event.h>
#include <media/v4l2-fwnode.h>
#include <media/v4l2-subdev.h>

#define IMX662_STANDBY		0x3000
#define IMX662_REGHOLD		0x3001
#define IMX662_XMSTA		0x3002
#define IMX662_INCK_SEL		0x3014
	#define IMX662_INCK_SEL_74_25	0x00
	#define IMX662_INCK_SEL_37_125	0x01
	#define IMX662_INCK_SEL_72	0x02
	#define IMX662_INCK_SEL_27	0x03
	#define IMX662_INCK_SEL_24	0x04
#define IMX662_LANE_RATE	0x3015
	#define IMX662_LANE_RATE_2376	0x00
	#define IMX662_LANE_RATE_2079	0x01
	#define IMX662_LANE_RATE_1782	0x02
	#define IMX662_LANE_RATE_1440	0x03
	#define IMX662_LANE_RATE_1188	0x04
	#define IMX662_LANE_RATE_891	0x05
	#define IMX662_LANE_RATE_720	0x06
	#define IMX662_LANE_RATE_594	0x07
#define IMX662_FLIP_WINMODEH	0x3020
#define IMX662_FLIP_WINMODEV	0x3021
#define IMX662_ADBIT		0x3022
#define IMX662_MDBIT		0x3023
#define IMX662_VMAX		0x3028
	#define IMX662_VMAX_MAX		0x0fffff
#define IMX662_HMAX		0x302c
	#define IMX662_HMAX_MAX		0xffff
#define IMX662_FR_FDG_SEL0	0x3030
	#define IMX662_FDG_SEL0_LCG	0x00
	#define IMX662_FDG_SEL0_HCG	0x01
#define IMX662_FR_FDG_SEL1	0x3031
#define IMX662_FR_FDG_SEL2	0x3032
#define IMX662_CSI_LANE_MODE	0x3040
#define IMX662_EXPOSURE		0x3050
#define IMX662_GAIN		0x3070

#define IMX662_EXPOSURE_MIN	4
#define IMX662_EXPOSURE_STEP	1
/* Exposure must be this many lines less than VMAX */
#define IMX662_EXPOSURE_OFFSET  4

#define IMX662_NATIVE_WIDTH		1956U
#define IMX662_NATIVE_HEIGHT		1120U
#define IMX662_PIXEL_ARRAY_LEFT		8U
#define IMX662_PIXEL_ARRAY_TOP		8U
//#define IMX662_PIXEL_ARRAY_LEFT		0U
//#define IMX662_PIXEL_ARRAY_TOP		20U
#define IMX662_PIXEL_ARRAY_WIDTH	1920U
#define IMX662_PIXEL_ARRAY_HEIGHT	1080U
//#define IMX662_PIXEL_ARRAY_WIDTH	1936U
//#define IMX662_PIXEL_ARRAY_HEIGHT	1100U

static const char * const imx662_supply_name[] = {
	"vdda",
	"vddd",
	"vdddo",
};

#define IMX662_NUM_SUPPLIES ARRAY_SIZE(imx662_supply_name)

struct imx662_regval {
	u16 reg;
	u8 val;
};

struct imx662_mode {
	u32 width;
	u32 height;
	u32 hmax;
	u32 vmax;
	struct v4l2_rect crop;

	const struct imx662_regval *mode_data;
	u32 mode_data_size;
};

struct imx662 {
	struct device *dev;
	struct clk *xclk;
	u8 inck_sel;
	struct regmap *regmap;
	u8 nlanes;
	u8 bpp;

	const struct imx662_pixfmt *formats;

	struct v4l2_subdev sd;
	struct media_pad pad;
	struct v4l2_mbus_framefmt current_format;
	const struct imx662_mode *current_mode;

	struct regulator_bulk_data supplies[IMX662_NUM_SUPPLIES];
	struct gpio_desc *rst_gpio;

	struct v4l2_ctrl_handler ctrls;
	struct v4l2_ctrl *pixel_rate;
	struct v4l2_ctrl *hblank;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hflip;
	struct v4l2_ctrl *vflip;
	struct v4l2_ctrl *exposure;

	struct mutex lock;
};

struct imx662_pixfmt {
	u32 code;
	u8 bpp;
};

#define IMX662_NUM_FORMATS 2

static const struct imx662_pixfmt imx662_colour_formats[IMX662_NUM_FORMATS] = {
	{ MEDIA_BUS_FMT_SRGGB10_1X10, 10 },
	{ MEDIA_BUS_FMT_SRGGB12_1X12, 12 },
};

static const struct imx662_pixfmt imx662_mono_formats[IMX662_NUM_FORMATS] = {
	{ MEDIA_BUS_FMT_Y10_1X10, 10 },
	{ MEDIA_BUS_FMT_Y12_1X12, 12 },
};

static const struct regmap_config imx662_regmap_config = {
	.reg_bits = 16,
	.val_bits = 8,
	.cache_type = REGCACHE_RBTREE,
};

static const struct imx662_regval imx662_global_settings[] = {
	{0x3002, 0x00}, //#Master mode operation start
	{0x301A, 0x00}, // HDR mode select (Normal)
	{0x301B, 0x00}, // Normal/binning
	{0x301C, 0x00}, // XVS sub sample
	{0x301E, 0x01}, // virtual channel
	//{0x302C, 0x94}, // HMAX 0x0294 30fps, adviced by 6by9
	//{0x302D, 0x02}, // HMAX 0x0294 30fps, adviced by 6by9
	{0x303C, 0x00}, // PIX HSTART
	{0x303D, 0x00}, // PIX HSTART
	{0x303E, 0x90}, // H WIDTH
	{0x303F, 0x07}, // H WIDTH
	{0x3044, 0x00}, // PIX VSTART
	{0x3045, 0x00}, // PIX VSTART
	{0x3046, 0x4C}, // V WIDTH
	{0x3047, 0x04}, // V WIDTH
	{0x3060, 0x16}, // DOL output timing
	{0x3061, 0x01}, // DOL output timing
	{0x3062, 0x00}, // DOL output timing
	{0x3064, 0xC4}, // DOL output timing
	{0x3065, 0x0C}, // DOL output timing
	{0x3066, 0x00}, // DOL output timing
	{0x3069, 0x00}, // Direct Gain Enable
	{0x3072, 0x00}, // GAIN SEF1
	{0x3073, 0x00}, // GAIN SEF1
	{0x3074, 0x00}, // GAIN SEF2
	{0x3075, 0x00}, // GAIN SEF2
	{0x3081, 0x00}, // EXP_GAIN
	{0x308C, 0x00}, // Clear HDR DGAIN
	{0x308D, 0x01}, // Clear HDR DGAIN
	{0x3094, 0x00}, // CHDR AGAIN LG
	{0x3095, 0x00}, // CHDR AGAIN LG
	{0x3096, 0x00}, // CHDR AGAIN1
	{0x3097, 0x00}, // CHDR AGAIN1
	{0x309C, 0x00}, // CHDR AGAIN HG
	{0x309D, 0x00}, // CHDR AGAIN HG
	{0x30A4, 0xAA}, // XVS/XHS OUT
	{0x30A6, 0x0F}, // XVS/XHS DRIVE HiZ
	{0x30CC, 0x00}, // XVS width
	{0x30CD, 0x00}, // XHS width
	{0x3400, 0x01}, // GAIN Adjust
	{0x3444, 0xAC}, // RESERVED
	{0x3460, 0x21}, // Normal Mode 22H=C HDR mode
	{0x3492, 0x08}, // RESERVED
	{0x3A50, 0xFF}, // Normal 12bit
	{0x3A51, 0x03}, // Normal 12bit
	{0x3A52, 0x00}, // AD 12bit
	{0x3B00, 0x39}, // RESERVED
	{0x3B23, 0x2D}, // RESERVED
	{0x3B45, 0x04}, // RESERVED
	{0x3C0A, 0x1F}, // RESERVED
	{0x3C0B, 0x1E}, // RESERVED
	{0x3C38, 0x21}, // RESERVED
	{0x3C40, 0x06}, // Normal mode. CHDR=05h
	{0x3C44, 0x00}, // RESERVED
	{0x3CB6, 0xD8}, // RESERVED
	{0x3CC4, 0xDA}, // RESERVED
	{0x3E24, 0x79}, // RESERVED
	{0x3E2C, 0x15}, // RESERVED
	{0x3EDC, 0x2D}, // RESERVED
	{0x4498, 0x05}, // RESERVED
	{0x449C, 0x19}, // RESERVED
	{0x449D, 0x00}, // RESERVED
	{0x449E, 0x32}, // RESERVED
	{0x449F, 0x01}, // RESERVED
	{0x44A0, 0x92}, // RESERVED
	{0x44A2, 0x91}, // RESERVED
	{0x44A4, 0x8C}, // RESERVED
	{0x44A6, 0x87}, // RESERVED
	{0x44A8, 0x82}, // RESERVED
	{0x44AA, 0x78}, // RESERVED
	{0x44AC, 0x6E}, // RESERVED
	{0x44AE, 0x69}, // RESERVED
	{0x44B0, 0x92}, // RESERVED
	{0x44B2, 0x91}, // RESERVED
	{0x44B4, 0x8C}, // RESERVED
	{0x44B6, 0x87}, // RESERVED
	{0x44B8, 0x82}, // RESERVED
	{0x44BA, 0x78}, // RESERVED
	{0x44BC, 0x6E}, // RESERVED
	{0x44BE, 0x69}, // RESERVED
	{0x44C1, 0x01}, // RESERVED
	{0x44C2, 0x7F}, // RESERVED
	{0x44C3, 0x01}, // RESERVED
	{0x44C4, 0x7A}, // RESERVED
	{0x44C5, 0x01}, // RESERVED
	{0x44C6, 0x7A}, // RESERVED
	{0x44C7, 0x01}, // RESERVED
	{0x44C8, 0x70}, // RESERVED
	{0x44C9, 0x01}, // RESERVED
	{0x44CA, 0x6B}, // RESERVED
	{0x44CB, 0x01}, // RESERVED
	{0x44CC, 0x6B}, // RESERVED
	{0x44CD, 0x01}, // RESERVED
	{0x44CE, 0x5C}, // RESERVED
	{0x44CF, 0x01}, // RESERVED
	{0x44D0, 0x7F}, // RESERVED
	{0x44D1, 0x01}, // RESERVED
	{0x44D2, 0x7F}, // RESERVED
	{0x44D3, 0x01}, // RESERVED
	{0x44D4, 0x7A}, // RESERVED
	{0x44D5, 0x01}, // RESERVED
	{0x44D6, 0x7A}, // RESERVED
	{0x44D7, 0x01}, // RESERVED
	{0x44D8, 0x70}, // RESERVED
	{0x44D9, 0x01}, // RESERVED
	{0x44DA, 0x6B}, // RESERVED
	{0x44DB, 0x01}, // RESERVED
	{0x44DC, 0x6B}, // RESERVED
	{0x44DD, 0x01}, // RESERVED
	{0x44DE, 0x5C}, // RESERVED
	{0x44DF, 0x01}, // RESERVED
	{0x4534, 0x1C}, // RESERVED
	{0x4535, 0x03}, // RESERVED
	{0x4538, 0x1C}, // RESERVED
	{0x4539, 0x1C}, // RESERVED
	{0x453A, 0x1C}, // RESERVED
	{0x453B, 0x1C}, // RESERVED
	{0x453C, 0x1C}, // RESERVED
	{0x453D, 0x1C}, // RESERVED
	{0x453E, 0x1C}, // RESERVED
	{0x453F, 0x1C}, // RESERVED
	{0x4540, 0x1C}, // RESERVED
	{0x4541, 0x03}, // RESERVED
	{0x4542, 0x03}, // RESERVED
	{0x4543, 0x03}, // RESERVED
	{0x4544, 0x03}, // RESERVED
	{0x4545, 0x03}, // RESERVED
	{0x4546, 0x03}, // RESERVED
	{0x4547, 0x03}, // RESERVED
	{0x4548, 0x03}, // RESERVED
	{0x4549, 0x03}, // RESERVED
};

static const struct imx662_regval imx662_1080p_common_settings[] = {
/* mode settings */
{0x3018, 0x00}, // WINMODE
{ IMX662_FR_FDG_SEL1, 0x00 },
{ IMX662_FR_FDG_SEL2, 0x00 },
//{ IMX662_FR_FDG_SEL1, 0x01 },
//{ IMX662_FR_FDG_SEL2, 0x01 },
};

static const struct imx662_regval imx662_2k60_settings[] = {
{0x301A, 0x00}, // WDMODE Normal mode
{0x301B, 0x00}, // ADDMODE non-binning
{0x3022, 0x00}, // ADBIT 10-bit
{0x3023, 0x01}, // MDBIT 12-bit
{0x3A50, 0x62}, // Normal 12bit
{0x3A51, 0x01}, // Normal 12bit
{0x3A52, 0x19}, // AD 12bit
};

/* supported link frequencies */
static const s64 imx662_link_freq_2lanes[] = {
//800000000,
594000000,
};

static const s64 imx662_link_freq_4lanes[] = {
	297000000,
};

/*
 * In this function and in the similar ones below we rely on imx662_probe()
 * to ensure that nlanes is either 2 or 4.
 */
static inline const s64 *imx662_link_freqs_ptr(const struct imx662 *imx662)
{
	if (imx662->nlanes == 2)
		return imx662_link_freq_2lanes;
	else
		return imx662_link_freq_4lanes;
}

static inline int imx662_link_freqs_num(const struct imx662 *imx662)
{
        if (imx662->nlanes == 2)
                return ARRAY_SIZE(imx662_link_freq_2lanes);
        else
                return ARRAY_SIZE(imx662_link_freq_4lanes);
}

/* Mode configs */
static const struct imx662_mode imx662_modes[] = {
        {
                /* 2K60 all pixel readout */
                .width = 1936,
                .height = 1100,
                .hmax = (990 * 2),
                .vmax = 0x04e2,
                .crop = {
                        .left = IMX662_PIXEL_ARRAY_LEFT,
                        .top = IMX662_PIXEL_ARRAY_TOP,
                        .width = IMX662_NATIVE_WIDTH,
                        .height = IMX662_NATIVE_HEIGHT,
                },
                .mode_data = imx662_2k60_settings,
                .mode_data_size = ARRAY_SIZE(imx662_2k60_settings),
        },
        {
                /*
                 * Note that this mode reads out the areas documented as
                 * "effective matrgin for color processing" and "effective pixel
                 * ignored area" in the datasheet.
                 */
                .width = 1936,
                .height = 1100,
                .hmax = (1980 * 2), // 0x0284 @720Mbps case
                //.hmax = (0x3de * 2), // 0x0284 @1188Mbps case
                .vmax = 0x04e2, //0x0ea6, // 30fps, default 0x04e2
                .crop = {
                        .left = IMX662_PIXEL_ARRAY_LEFT,
                        .top = IMX662_PIXEL_ARRAY_TOP,
                        .width = IMX662_NATIVE_WIDTH,
                        .height = IMX662_NATIVE_HEIGHT,
                },
                .mode_data = imx662_1080p_common_settings,
                .mode_data_size = ARRAY_SIZE(imx662_1080p_common_settings),
	},
};

#define IMX662_NUM_MODES ARRAY_SIZE(imx662_modes)

static inline struct imx662 *to_imx662(struct v4l2_subdev *_sd)
{
	return container_of(_sd, struct imx662, sd);
}

static inline int imx662_read_reg(struct imx662 *imx662, u16 addr, u8 *value)
{
	unsigned int regval;
	int ret;

	ret = regmap_read(imx662->regmap, addr, &regval);
	if (ret) {
		dev_err(imx662->dev, "I2C read failed for addr: %x\n", addr);
		return ret;
	}

	*value = regval & 0xff;

	return 0;
}

static int imx662_write_reg(struct imx662 *imx662, u16 addr, u8 value)
{
	int ret;

	ret = regmap_write(imx662->regmap, addr, value);
	if (ret) {
		dev_err(imx662->dev, "I2C write failed for addr: %x\n", addr);
		return ret;
	}

	return ret;
}

static int imx662_set_register_array(struct imx662 *imx662,
				     const struct imx662_regval *settings,
				     unsigned int num_settings)
{
	unsigned int i;
	int ret;

	for (i = 0; i < num_settings; ++i, ++settings) {
		ret = imx662_write_reg(imx662, settings->reg, settings->val);
		if (ret < 0)
			return ret;
	}

	/* Provide 10ms settle time */
	usleep_range(10000, 11000);

	return 0;
}

static int imx662_write_buffered_reg(struct imx662 *imx662, u16 address_low,
				     u8 nr_regs, u32 value)
{
	unsigned int i;
	int ret;

	ret = imx662_write_reg(imx662, IMX662_REGHOLD, 0x01);
	if (ret) {
		dev_err(imx662->dev, "Error setting hold register\n");
		return ret;
	}

	for (i = 0; i < nr_regs; i++) {
		ret = imx662_write_reg(imx662, address_low + i,
				       (u8)(value >> (i * 8)));
		if (ret) {
			dev_err(imx662->dev, "Error writing buffered registers\n");
			return ret;
		}
	}

	ret = imx662_write_reg(imx662, IMX662_REGHOLD, 0x00);
	if (ret) {
		dev_err(imx662->dev, "Error setting hold register\n");
		return ret;
	}

	return ret;
}

static int imx662_set_gain(struct imx662 *imx662, u32 value)
{
	int ret;

	ret = imx662_write_buffered_reg(imx662, IMX662_GAIN, 2, value);
	if (ret) {
		dev_err(imx662->dev, "Unable to write gain\n");
		return ret;
	}

	ret = imx662_write_reg(imx662, IMX662_FR_FDG_SEL0, value < 0x34 ?
	//ret = imx662_write_reg(imx662, IMX662_FR_FDG_SEL0, value < 0x22 ?
			       IMX662_FDG_SEL0_HCG : IMX662_FDG_SEL0_HCG);
			       //IMX662_FDG_SEL0_HCG : IMX662_FDG_SEL0_LCG);
	if (ret)
		dev_err(imx662->dev, "Unable to write LCG/HCG mode\n");

	return ret;
}

static int imx662_set_exposure(struct imx662 *imx662, u32 value)
{
	u32 exposure = (imx662->current_mode->height + imx662->vblank->val) -
						value - 1;
	int ret;

	ret = imx662_write_buffered_reg(imx662, IMX662_EXPOSURE, 3,
					exposure);
					//0x000004);
	if (ret)
		dev_err(imx662->dev, "Unable to write exposure\n");

	return ret;
}

static int imx662_set_hmax(struct imx662 *imx662, u32 val)
{
	u32 hmax = (val + imx662->current_mode->width) >> 1;
	int ret;

	ret = imx662_write_buffered_reg(imx662, IMX662_HMAX, 2,
					hmax);
	if (ret)
		dev_err(imx662->dev, "Error setting HMAX register\n");

	return ret;
}

static int imx662_set_vmax(struct imx662 *imx662, u32 val)
{
	u32 vmax = val + imx662->current_mode->height;

	int ret;

	ret = imx662_write_buffered_reg(imx662, IMX662_VMAX, 3,
					vmax);
					//0x000465);
	if (ret)
		dev_err(imx662->dev, "Unable to write vmax\n");

	/*
	 * Changing vblank changes the allowed range for exposure.
	 * We don't supply the current exposure as default here as it
	 * may lie outside the new range. We will reset it just below.
	 */
	__v4l2_ctrl_modify_range(imx662->exposure,
				 IMX662_EXPOSURE_MIN,
				 vmax - IMX662_EXPOSURE_OFFSET,
				 IMX662_EXPOSURE_STEP,
				 vmax - IMX662_EXPOSURE_OFFSET);

	/*
	 * Becuse of the way exposure works for this sensor, updating
	 * vblank causes the effective exposure to change, so we must
	 * set it back to the "new" correct value.
	 */
	imx662_set_exposure(imx662, imx662->exposure->val);

	return ret;
}

/* Stop streaming */
static int imx662_stop_streaming(struct imx662 *imx662)
{
	int ret;

	ret = imx662_write_reg(imx662, IMX662_STANDBY, 0x01);
	if (ret < 0)
		return ret;

	msleep(30);

	return imx662_write_reg(imx662, IMX662_XMSTA, 0x01);
}

static int imx662_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct imx662 *imx662 = container_of(ctrl->handler,
					     struct imx662, ctrls);
	int ret = 0;

	/* V4L2 controls values will be applied only when power is already up */
	if (!pm_runtime_get_if_in_use(imx662->dev))
		return 0;

	switch (ctrl->id) {
	case V4L2_CID_ANALOGUE_GAIN:
		ret = imx662_set_gain(imx662, ctrl->val);
		break;
	case V4L2_CID_EXPOSURE:
		ret = imx662_set_exposure(imx662, ctrl->val);
		break;
	case V4L2_CID_HBLANK:
		ret = imx662_set_hmax(imx662, ctrl->val);
		break;
	case V4L2_CID_VBLANK:
		ret = imx662_set_vmax(imx662, ctrl->val);
		break;
	case V4L2_CID_HFLIP:
		ret = imx662_write_reg(imx662, IMX662_FLIP_WINMODEH, ctrl->val);
		break;
	case V4L2_CID_VFLIP:
		ret = imx662_write_reg(imx662, IMX662_FLIP_WINMODEV, ctrl->val);
		break;
	default:
		ret = -EINVAL;
		break;
	}

	pm_runtime_put(imx662->dev);

	return ret;
}

static const struct v4l2_ctrl_ops imx662_ctrl_ops = {
	.s_ctrl = imx662_set_ctrl,
};

static int imx662_enum_mbus_code(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_mbus_code_enum *code)
{
	const struct imx662 *imx662 = to_imx662(sd);

	if (code->index >= IMX662_NUM_FORMATS)
		return -EINVAL;

	code->code = imx662->formats[code->index].code;

	return 0;
}

static int imx662_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	const struct imx662 *imx662 = to_imx662(sd);

	if (fse->code != imx662->formats[0].code &&
	    fse->code != imx662->formats[1].code)
		return -EINVAL;

	if (fse->index >= IMX662_NUM_MODES)
		return -EINVAL;

	fse->min_width = imx662_modes[fse->index].width;
	fse->max_width = imx662_modes[fse->index].width;
	fse->min_height = imx662_modes[fse->index].height;
	fse->max_height = imx662_modes[fse->index].height;

	return 0;
}

static int imx662_get_fmt(struct v4l2_subdev *sd,
			  struct v4l2_subdev_state *sd_state,
			  struct v4l2_subdev_format *fmt)
{
	struct imx662 *imx662 = to_imx662(sd);
	struct v4l2_mbus_framefmt *framefmt;

	mutex_lock(&imx662->lock);

	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		framefmt = v4l2_subdev_get_try_format(&imx662->sd, sd_state,
						      fmt->pad);
	else
		framefmt = &imx662->current_format;

	fmt->format = *framefmt;

	mutex_unlock(&imx662->lock);

	return 0;
}

static u64 imx662_calc_pixel_rate(struct imx662 *imx662)
{
	return 148500000;
}

static int imx662_set_fmt(struct v4l2_subdev *sd,
			  struct v4l2_subdev_state *sd_state,
			  struct v4l2_subdev_format *fmt)
{
	struct imx662 *imx662 = to_imx662(sd);
	const struct imx662_mode *mode;
	struct v4l2_mbus_framefmt *format;
	unsigned int i;

	mutex_lock(&imx662->lock);

	mode = v4l2_find_nearest_size(imx662_modes, IMX662_NUM_MODES,
				      width, height,
				      fmt->format.width, fmt->format.height);

	fmt->format.width = mode->width;
	fmt->format.height = mode->height;

	for (i = 0; i < IMX662_NUM_FORMATS; i++)
		if (imx662->formats[i].code == fmt->format.code)
			break;

	if (i >= IMX662_NUM_FORMATS)
		i = 0;

	fmt->format.code = imx662->formats[i].code;
	fmt->format.field = V4L2_FIELD_NONE;
	fmt->format.colorspace = V4L2_COLORSPACE_RAW;
	fmt->format.ycbcr_enc =
			V4L2_MAP_YCBCR_ENC_DEFAULT(fmt->format.colorspace);
	fmt->format.quantization =
		V4L2_MAP_QUANTIZATION_DEFAULT(true, fmt->format.colorspace,
					      fmt->format.ycbcr_enc);
	fmt->format.xfer_func =
		V4L2_MAP_XFER_FUNC_DEFAULT(fmt->format.colorspace);

	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY) {
		format = v4l2_subdev_get_try_format(sd, sd_state, fmt->pad);
	} else {
		format = &imx662->current_format;
		imx662->current_mode = mode;
		imx662->bpp = imx662->formats[i].bpp;

		if (imx662->pixel_rate)
			__v4l2_ctrl_s_ctrl_int64(imx662->pixel_rate,
						 imx662_calc_pixel_rate(imx662));

		if (imx662->hblank) {
			__v4l2_ctrl_modify_range(imx662->hblank,
						 mode->hmax - mode->width,
						 IMX662_HMAX_MAX - mode->width,
						 1, mode->hmax - mode->width);
			__v4l2_ctrl_s_ctrl(imx662->hblank,
					   mode->hmax - mode->width);
		}
		if (imx662->vblank) {
			__v4l2_ctrl_modify_range(imx662->vblank,
						 mode->vmax - mode->height,
						 IMX662_VMAX_MAX - mode->height,
						 1,
						 mode->vmax - mode->height);
			__v4l2_ctrl_s_ctrl(imx662->vblank,
					   mode->vmax - mode->height);
		}
		if (imx662->exposure)
			__v4l2_ctrl_modify_range(imx662->exposure,
						 IMX662_EXPOSURE_MIN,
						 mode->vmax - 2,
						 IMX662_EXPOSURE_STEP,
						 mode->vmax - 2);
	}

	*format = fmt->format;

	mutex_unlock(&imx662->lock);

	return 0;
}

static int imx662_entity_init_cfg(struct v4l2_subdev *subdev,
				  struct v4l2_subdev_state *sd_state)
{
	struct v4l2_subdev_format fmt = { 0 };

	fmt.which = sd_state ? V4L2_SUBDEV_FORMAT_TRY : V4L2_SUBDEV_FORMAT_ACTIVE;
	fmt.format.width = 1936;
	fmt.format.height = 1100;

	imx662_set_fmt(subdev, sd_state, &fmt);

	return 0;
}

static int imx662_write_current_format(struct imx662 *imx662)
{
	u8 ad_md_bit;
	int ret;

	switch (imx662->current_format.code) {
	case MEDIA_BUS_FMT_SRGGB10_1X10:
	case MEDIA_BUS_FMT_Y10_1X10:
		ad_md_bit = 0x00;
		break;
	case MEDIA_BUS_FMT_SRGGB12_1X12:
	case MEDIA_BUS_FMT_Y12_1X12:
		ad_md_bit = 0x01;
		break;
	default:
		dev_err(imx662->dev, "Unknown pixel format\n");
		return -EINVAL;
	}

	ret = imx662_write_reg(imx662, IMX662_ADBIT, ad_md_bit);
	if (ret < 0)
		return ret;

	ret = imx662_write_reg(imx662, IMX662_MDBIT, ad_md_bit);
	if (ret < 0)
		return ret;

	return 0;
}

static const struct v4l2_rect *
__imx662_get_pad_crop(struct imx662 *imx662,
		      struct v4l2_subdev_state *sd_state,
		      unsigned int pad, enum v4l2_subdev_format_whence which)
{
	switch (which) {
	case V4L2_SUBDEV_FORMAT_TRY:
		return v4l2_subdev_get_try_crop(&imx662->sd, sd_state, pad);
	case V4L2_SUBDEV_FORMAT_ACTIVE:
		return &imx662->current_mode->crop;
	}

	return NULL;
}

static int imx662_get_selection(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *sd_state,
				struct v4l2_subdev_selection *sel)
{
	switch (sel->target) {
	case V4L2_SEL_TGT_CROP: {
		struct imx662 *imx662 = to_imx662(sd);

		mutex_lock(&imx662->lock);
		sel->r = *__imx662_get_pad_crop(imx662, sd_state, sel->pad,
						sel->which);
		mutex_unlock(&imx662->lock);

		return 0;
	}

	case V4L2_SEL_TGT_NATIVE_SIZE:
		sel->r.top = 0;
		sel->r.left = 0;
		sel->r.width = IMX662_NATIVE_WIDTH;
		sel->r.height = IMX662_NATIVE_HEIGHT;

		return 0;

	case V4L2_SEL_TGT_CROP_DEFAULT:
	case V4L2_SEL_TGT_CROP_BOUNDS:
		sel->r.top = IMX662_PIXEL_ARRAY_TOP;
		sel->r.left = IMX662_PIXEL_ARRAY_LEFT;
		sel->r.width = IMX662_PIXEL_ARRAY_WIDTH;
		sel->r.height = IMX662_PIXEL_ARRAY_HEIGHT;

		return 0;
	}

	return -EINVAL;
}

/* Start streaming */
static int imx662_start_streaming(struct imx662 *imx662)
{
	int ret;

	/* Set init register settings */
	ret = imx662_set_register_array(imx662, imx662_global_settings,
					ARRAY_SIZE(imx662_global_settings));
        if (ret < 0) {
                dev_err(imx662->dev, "Could not set init registers\n");
                return ret;
        }
        dev_dbg(imx662->dev, "write INCK_SEL with %02x\n", imx662->inck_sel);
	ret = imx662_write_reg(imx662, IMX662_INCK_SEL, imx662->inck_sel);
	if (ret < 0)
		return ret;

	/* Apply the register values related to current frame format */
	ret = imx662_write_current_format(imx662);
	if (ret < 0) {
		dev_err(imx662->dev, "Could not set frame format\n");
		return ret;
	}

	/* Apply default values of current mode */
	ret = imx662_set_register_array(imx662,
					imx662->current_mode->mode_data,
					imx662->current_mode->mode_data_size);
	if (ret < 0) {
		dev_err(imx662->dev, "Could not set current mode\n");
		return ret;
	}

	/* Apply lane config registers of current mode */
	ret = imx662_write_reg(imx662, IMX662_CSI_LANE_MODE,
			       imx662->nlanes == 2 ? 0x01 : 0x03);
	if (ret < 0)
		return ret;

	ret = imx662_write_reg(imx662, IMX662_LANE_RATE,
			       //imx662->nlanes == 2 ? IMX662_LANE_RATE_720 : // for FPD Limk III
			       imx662->nlanes == 2 ? IMX662_LANE_RATE_1188 :
			       //imx662->nlanes == 2 ? IMX662_LANE_RATE_1188 :
						     IMX662_LANE_RATE_594);
	if (ret < 0)
		return ret;

	/* Apply customized values from user */
	ret = v4l2_ctrl_handler_setup(imx662->sd.ctrl_handler);
	if (ret) {
		dev_err(imx662->dev, "Could not sync v4l2 controls\n");
		return ret;
	}

	ret = imx662_write_reg(imx662, IMX662_STANDBY, 0x00);
	if (ret < 0)
		return ret;

	msleep(30);

	/* Start streaming */
	return imx662_write_reg(imx662, IMX662_XMSTA, 0x00);
}

static int imx662_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct imx662 *imx662 = to_imx662(sd);
	int ret = 0;

	if (enable) {
		ret = pm_runtime_resume_and_get(imx662->dev);
		if (ret < 0)
			goto unlock_and_return;

		ret = imx662_start_streaming(imx662);
		if (ret) {
			dev_err(imx662->dev, "Start stream failed\n");
			pm_runtime_put(imx662->dev);
			goto unlock_and_return;
		}
	} else {
		imx662_stop_streaming(imx662);
		pm_runtime_put(imx662->dev);
	}
	/* vflip and hflip cannot change during streaming */
	__v4l2_ctrl_grab(imx662->vflip, enable);
	__v4l2_ctrl_grab(imx662->hflip, enable);

unlock_and_return:

	return ret;
}

static int imx662_get_regulators(struct device *dev, struct imx662 *imx662)
{
	unsigned int i;

	for (i = 0; i < IMX662_NUM_SUPPLIES; i++)
		imx662->supplies[i].supply = imx662_supply_name[i];

	return devm_regulator_bulk_get(dev, IMX662_NUM_SUPPLIES,
				       imx662->supplies);
}

static int imx662_power_on(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct imx662 *imx662 = to_imx662(sd);
	int ret;

	ret = clk_prepare_enable(imx662->xclk);
	if (ret) {
		dev_err(dev, "Failed to enable clock\n");
		return ret;
	}

	ret = regulator_bulk_enable(IMX662_NUM_SUPPLIES, imx662->supplies);
	if (ret) {
		dev_err(dev, "Failed to enable regulators\n");
		clk_disable_unprepare(imx662->xclk);
		return ret;
	}

	usleep_range(1, 2);
	gpiod_set_value_cansleep(imx662->rst_gpio, 0);
	usleep_range(30000, 31000);

	return 0;
}

static int imx662_power_off(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);
	struct imx662 *imx662 = to_imx662(sd);

	clk_disable_unprepare(imx662->xclk);
	gpiod_set_value_cansleep(imx662->rst_gpio, 1);
	regulator_bulk_disable(IMX662_NUM_SUPPLIES, imx662->supplies);

	return 0;
}

static const struct dev_pm_ops imx662_pm_ops = {
	SET_RUNTIME_PM_OPS(imx662_power_off, imx662_power_on, NULL)
};

static const struct v4l2_subdev_core_ops imx662_core_ops = {
	.subscribe_event = v4l2_ctrl_subdev_subscribe_event,
	.unsubscribe_event = v4l2_event_subdev_unsubscribe,
};

static const struct v4l2_subdev_video_ops imx662_video_ops = {
	.s_stream = imx662_set_stream,
};

static const struct v4l2_subdev_pad_ops imx662_pad_ops = {
	.init_cfg = imx662_entity_init_cfg,
	.enum_mbus_code = imx662_enum_mbus_code,
	.enum_frame_size = imx662_enum_frame_size,
	.get_fmt = imx662_get_fmt,
	.set_fmt = imx662_set_fmt,
	.get_selection = imx662_get_selection,
};

static const struct v4l2_subdev_ops imx662_subdev_ops = {
	.core = &imx662_core_ops,
	.video = &imx662_video_ops,
	.pad = &imx662_pad_ops,
};

static const struct media_entity_operations imx662_subdev_entity_ops = {
	.link_validate = v4l2_subdev_link_validate,
};

/*
 * Returns 0 if all link frequencies used by the driver for the given number
 * of MIPI data lanes are mentioned in the device tree, or the value of the
 * first missing frequency otherwise.
 */
static s64 imx662_check_link_freqs(const struct imx662 *imx662,
				   const struct v4l2_fwnode_endpoint *ep)
{
	int i, j;
	const s64 *freqs = imx662_link_freqs_ptr(imx662);
	int freqs_count = imx662_link_freqs_num(imx662);

	for (i = 0; i < freqs_count; i++) {
		for (j = 0; j < ep->nr_of_link_frequencies; j++)
			if (freqs[i] == ep->link_frequencies[j])
				break;
		if (j == ep->nr_of_link_frequencies)
			return freqs[i];
	}
	return 0;
}

static const struct of_device_id imx662_of_match[] = {
	{ .compatible = "sony,imx662", .data = imx662_colour_formats },
	{ .compatible = "sony,imx662-mono", .data = imx662_mono_formats },
	{ /* sentinel */ }
};

static int imx662_probe(struct i2c_client *client,
		const struct i2c_device_id *id)
{
	struct v4l2_fwnode_device_properties props;
	struct device *dev = &client->dev;
	struct fwnode_handle *endpoint;
	/* Only CSI2 is supported for now: */
	struct v4l2_fwnode_endpoint ep = {
		.bus_type = V4L2_MBUS_CSI2_DPHY
	};
	const struct of_device_id *match;
	const struct imx662_mode *mode;
	struct v4l2_ctrl *ctrl;
	struct imx662 *imx662;
	u32 xclk_freq;
	s64 fq;
	int ret;

	/* Suppress unused parameter warning on kernels that still pass @id */
	(void)id;

	imx662 = devm_kzalloc(dev, sizeof(*imx662), GFP_KERNEL);
	if (!imx662)
		return -ENOMEM;

	imx662->dev = dev;
	imx662->regmap = devm_regmap_init_i2c(client, &imx662_regmap_config);
	if (IS_ERR(imx662->regmap)) {
		dev_err(dev, "Unable to initialize I2C\n");
		return -ENODEV;
	}

	match = of_match_device(imx662_of_match, dev);
	if (!match)
		return -ENODEV;
	imx662->formats = (const struct imx662_pixfmt *)match->data;

	endpoint = fwnode_graph_get_next_endpoint(dev_fwnode(dev), NULL);
	if (!endpoint) {
		dev_err(dev, "Endpoint node not found\n");
		return -EINVAL;
	}

	ret = v4l2_fwnode_endpoint_alloc_parse(endpoint, &ep);
	fwnode_handle_put(endpoint);
	if (ret == -ENXIO) {
		dev_err(dev, "Unsupported bus type, should be CSI2\n");
		goto free_err;
	} else if (ret) {
		dev_err(dev, "Parsing endpoint node failed\n");
		goto free_err;
	}

	/* Get number of data lanes */
	imx662->nlanes = ep.bus.mipi_csi2.num_data_lanes;
	if (imx662->nlanes != 2 && imx662->nlanes != 4) {
		dev_err(dev, "Invalid data lanes: %d\n", imx662->nlanes);
		ret = -EINVAL;
		goto free_err;
	}

	dev_dbg(dev, "Using %u data lanes\n", imx662->nlanes);

	if (!ep.nr_of_link_frequencies) {
		dev_err(dev, "link-frequency property not found in DT\n");
		ret = -EINVAL;
		goto free_err;
	}

	/* Check that link frequences for all the modes are in device tree */
	fq = imx662_check_link_freqs(imx662, &ep);
	if (fq) {
		dev_err(dev, "Link frequency of %lld is not supported\n", fq);
		ret = -EINVAL;
		goto free_err;
	}

	/* get system clock (xclk) */
	imx662->xclk = devm_clk_get(dev, "xclk");
	if (IS_ERR(imx662->xclk)) {
		dev_err(dev, "Could not get xclk");
		ret = PTR_ERR(imx662->xclk);
		goto free_err;
	}

	ret = fwnode_property_read_u32(dev_fwnode(dev), "clock-frequency",
				       &xclk_freq);
	if (ret) {
		dev_err(dev, "Could not get xclk frequency\n");
		goto free_err;
	}

	/* external clock can be one of a range of values - validate it */
	switch (xclk_freq) {
	case 74250000:
		imx662->inck_sel = IMX662_INCK_SEL_74_25;
		break;
	case 37125000:
		imx662->inck_sel = IMX662_INCK_SEL_37_125;
		break;
	case 72000000:
		imx662->inck_sel = IMX662_INCK_SEL_72;
		break;
	case 27000000:
		imx662->inck_sel = IMX662_INCK_SEL_27;
		break;
	case 24000000:
		imx662->inck_sel = IMX662_INCK_SEL_24;
		break;
	default:
		dev_err(dev, "External clock frequency %u is not supported\n",
			xclk_freq);
		ret = -EINVAL;
		goto free_err;
	}

	ret = clk_set_rate(imx662->xclk, xclk_freq);
	if (ret) {
		dev_err(dev, "Could not set xclk frequency\n");
		goto free_err;
	}

	ret = imx662_get_regulators(dev, imx662);
	if (ret < 0) {
		dev_err(dev, "Cannot get regulators\n");
		goto free_err;
	}

	imx662->rst_gpio = devm_gpiod_get_optional(dev, "reset",
						   GPIOD_OUT_HIGH);
	if (IS_ERR(imx662->rst_gpio)) {
		dev_err(dev, "Cannot get reset gpio\n");
		ret = PTR_ERR(imx662->rst_gpio);
		goto free_err;
	}

	mutex_init(&imx662->lock);

	/*
	 * Initialize the frame format. In particular, imx662->current_mode
	 * and imx662->bpp are set to defaults: imx662_calc_pixel_rate() call
	 * below relies on these fields.
	 */
	imx662_entity_init_cfg(&imx662->sd, NULL);

	v4l2_ctrl_handler_init(&imx662->ctrls, 11);

	v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
			  V4L2_CID_ANALOGUE_GAIN, 0, 100, 1, 0);

	mode = imx662->current_mode;
	imx662->hblank = v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
					   V4L2_CID_HBLANK,
					   mode->hmax - mode->width,
					   IMX662_HMAX_MAX - mode->width, 1,
					   mode->hmax - mode->width);

	imx662->vblank = v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
					   V4L2_CID_VBLANK,
					   mode->vmax - mode->height,
					   IMX662_VMAX_MAX - mode->height, 1,
					   mode->vmax - mode->height);

	imx662->exposure = v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
					     V4L2_CID_EXPOSURE,
					     IMX662_EXPOSURE_MIN,
					     mode->vmax - 2,
					     IMX662_EXPOSURE_STEP,
					     mode->vmax - 2);

	imx662->hflip = v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
					  V4L2_CID_HFLIP, 0, 1, 1, 0);
	imx662->vflip = v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
					  V4L2_CID_VFLIP, 0, 1, 1, 0);

	ctrl = v4l2_ctrl_new_int_menu(&imx662->ctrls, &imx662_ctrl_ops,
				      V4L2_CID_LINK_FREQ,
				      imx662_link_freqs_num(imx662) - 1, 0,
				      imx662_link_freqs_ptr(imx662));
	if (ctrl)
		ctrl->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	imx662->pixel_rate = v4l2_ctrl_new_std(&imx662->ctrls, &imx662_ctrl_ops,
					       V4L2_CID_PIXEL_RATE,
					       1, INT_MAX, 1,
					       imx662_calc_pixel_rate(imx662));

	ret = v4l2_fwnode_device_parse(&client->dev, &props);
	if (ret)
		goto free_ctrl;

	ret = v4l2_ctrl_new_fwnode_properties(&imx662->ctrls, &imx662_ctrl_ops,
					      &props);
	if (ret)
		goto free_ctrl;

	imx662->sd.ctrl_handler = &imx662->ctrls;

	if (imx662->ctrls.error) {
		dev_err(dev, "Control initialization error %d\n",
			imx662->ctrls.error);
		ret = imx662->ctrls.error;
		goto free_ctrl;
	}

	v4l2_i2c_subdev_init(&imx662->sd, client, &imx662_subdev_ops);
	imx662->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE |
		V4L2_SUBDEV_FL_HAS_EVENTS;
	imx662->sd.dev = &client->dev;
	imx662->sd.entity.ops = &imx662_subdev_entity_ops;
	imx662->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;

	imx662->pad.flags = MEDIA_PAD_FL_SOURCE;
	ret = media_entity_pads_init(&imx662->sd.entity, 1, &imx662->pad);
	if (ret < 0) {
		dev_err(dev, "Could not register media entity\n");
		goto free_ctrl;
	}

	/* Initialize the frame format (this also sets imx662->current_mode) */
	imx662_entity_init_cfg(&imx662->sd, NULL);

	ret = v4l2_async_register_subdev(&imx662->sd);
	if (ret < 0) {
		dev_err(dev, "Could not register v4l2 device\n");
		goto free_entity;
	}

	/* Power on the device to match runtime PM state below */
	ret = imx662_power_on(dev);
	if (ret < 0) {
		dev_err(dev, "Could not power on the device\n");
		goto free_entity;
	}

	pm_runtime_set_active(dev);
	pm_runtime_enable(dev);
	pm_runtime_idle(dev);

	v4l2_fwnode_endpoint_free(&ep);

	return 0;

free_entity:
	media_entity_cleanup(&imx662->sd.entity);
free_ctrl:
	v4l2_ctrl_handler_free(&imx662->ctrls);
	mutex_destroy(&imx662->lock);
free_err:
	v4l2_fwnode_endpoint_free(&ep);

	return ret;
}

/*
static int imx662_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct imx662 *imx662 = to_imx662(sd);

	v4l2_async_unregister_subdev(sd);
	media_entity_cleanup(&sd->entity);
	v4l2_ctrl_handler_free(sd->ctrl_handler);

	mutex_destroy(&imx662->lock);

	pm_runtime_disable(imx662->dev);
	if (!pm_runtime_status_suspended(imx662->dev))
		imx662_power_off(imx662->dev);
	pm_runtime_set_suspended(imx662->dev);

	return 0;
}
*/

MODULE_DEVICE_TABLE(of, imx662_of_match);

static struct i2c_driver imx662_i2c_driver = {
	.probe  = imx662_probe,
	//.probe_new  = imx662_probe,
	//.remove = imx662_remove,
	.driver = {
		.name  = "imx662",
		.pm = &imx662_pm_ops,
		.of_match_table = of_match_ptr(imx662_of_match),
	},
};

module_i2c_driver(imx662_i2c_driver);

MODULE_DESCRIPTION("Sony IMX662 CMOS Image Sensor Driver");
MODULE_AUTHOR("Soho Enterprise Ltd.");
MODULE_AUTHOR("Tetsuya Nomura <tetsuya.nomura@soho-enterprise.com>");
MODULE_LICENSE("GPL v2");
