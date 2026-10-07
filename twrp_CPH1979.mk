# Inherit from the base products first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)

# Inherit from our device.
$(call inherit-product, device/oppo/CPH1979/device.mk)

PRODUCT_DEVICE := CPH1979
PRODUCT_NAME := twrp_CPH1979
PRODUCT_BRAND := OPPO
PRODUCT_MODEL := CPH1979
PRODUCT_MANUFACTURER := OPPO
