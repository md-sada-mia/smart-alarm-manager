#!/usr/bin/env python3
"""
Icon Generator Script for Smart Alarm Manager
Generates all required Android icons from final-logo.png
"""

from PIL import Image
import os

# Base paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SOURCE_LOGO = os.path.join(BASE_DIR, 'final-logo.png')
ANDROID_RES = os.path.join(BASE_DIR, 'android', 'app', 'src', 'main', 'res')

# Icon configurations
LAUNCHER_ICONS = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

FOREGROUND_ICONS = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
}

NOTIFICATION_ICONS = {
    'mdpi': 24,
    'hdpi': 36,
    'xhdpi': 48,
    'xxhdpi': 72,
    'xxxhdpi': 96,
}


def create_notification_icon(source_img, size):
    """
    Create a monochrome notification icon (white silhouette on transparent background)
    Android notification icons should be white icons on a transparent background.
    
    The source logo has a pink background with a white location pin.
    We need to extract the white shape and convert it to a white silhouette.
    """
    # Resize the source image
    img = source_img.copy()
    img = img.resize((size, size), Image.Resampling.LANCZOS)
    
    # Convert to RGBA if not already
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # Create a new image with transparent background
    notification_icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # Get pixel data
    pixels = img.load()
    new_pixels = notification_icon.load()
    
    # The pink background is approximately RGB(255, 0, 255) or #FF00FF
    # The white icon is approximately RGB(240-255, 240-255, 240-255)
    # We want to keep the white icon parts and make the pink background transparent
    
    for y in range(size):
        for x in range(size):
            r, g, b, a = pixels[x, y]
            
            # Check if pixel is part of the white icon (high luminance)
            # or part of the pink background (magenta color)
            luminance = (r + g + b) / 3
            
            # If it's a bright pixel (white-ish), keep it as white
            # Pink has R=255, G=0, B=255, so G is very low
            # White has R~255, G~255, B~255, so all channels are high
            is_white_icon = (luminance > 200 and g > 150)  # High luminance and green channel
            is_pink_magenta = (r > 200 and b > 200 and g < 100)  # Pink/magenta color
            
            if is_white_icon and not is_pink_magenta:
                # This is part of the icon, make it white with full opacity
                new_pixels[x, y] = (255, 255, 255, 255)
            else:
                # This is background or pink area, make it transparent
                new_pixels[x, y] = (0, 0, 0, 0)
    
    return notification_icon


def generate_icons():
    """Generate all required icons from the source logo"""
    
    # Check if source logo exists
    if not os.path.exists(SOURCE_LOGO):
        print(f"❌ Error: Source logo not found at {SOURCE_LOGO}")
        return False
    
    print(f"📱 Starting icon generation from: {SOURCE_LOGO}")
    
    # Load source image
    try:
        source_img = Image.open(SOURCE_LOGO)
        print(f"✅ Loaded source image: {source_img.size[0]}x{source_img.size[1]}")
    except Exception as e:
        print(f"❌ Error loading source image: {e}")
        return False
    
    # Convert to RGBA if needed
    if source_img.mode != 'RGBA':
        source_img = source_img.convert('RGBA')
    
    total_icons = 0
    
    # Generate launcher icons
    print("\n🚀 Generating launcher icons...")
    for density, size in LAUNCHER_ICONS.items():
        mipmap_dir = os.path.join(ANDROID_RES, f'mipmap-{density}')
        os.makedirs(mipmap_dir, exist_ok=True)
        
        # Resize and save ic_launcher.png
        launcher_icon = source_img.resize((size, size), Image.Resampling.LANCZOS)
        ic_launcher_path = os.path.join(mipmap_dir, 'ic_launcher.png')
        launcher_icon.save(ic_launcher_path, 'PNG')
        print(f"  ✓ {density}: ic_launcher.png ({size}x{size})")
        total_icons += 1
        
        # Also save as launcher_icon.png (used by notification service)
        launcher_icon_path = os.path.join(mipmap_dir, 'launcher_icon.png')
        launcher_icon.save(launcher_icon_path, 'PNG')
        print(f"  ✓ {density}: launcher_icon.png ({size}x{size})")
        total_icons += 1
    
    # Generate foreground icons for adaptive icons
    print("\n🎨 Generating foreground icons...")
    for density, size in FOREGROUND_ICONS.items():
        drawable_dir = os.path.join(ANDROID_RES, f'drawable-{density}')
        os.makedirs(drawable_dir, exist_ok=True)
        
        # Create foreground icon with padding for adaptive icon safe zone
        # Adaptive icons should have content in the center 66dp diameter circle
        # So we add padding to ensure the icon fits properly
        padding = int(size * 0.25)  # 25% padding on each side
        foreground_size = size - (2 * padding)
        
        # Create canvas
        foreground_icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        
        # Resize logo to fit in safe zone
        logo_resized = source_img.resize((foreground_size, foreground_size), Image.Resampling.LANCZOS)
        
        # Paste logo in center
        foreground_icon.paste(logo_resized, (padding, padding), logo_resized)
        
        # Save
        foreground_path = os.path.join(drawable_dir, 'ic_launcher_foreground.png')
        foreground_icon.save(foreground_path, 'PNG')
        print(f"  ✓ {density}: ic_launcher_foreground.png ({size}x{size})")
        total_icons += 1
    
    # Generate notification icons (monochrome silhouette)
    print("\n🔔 Generating notification icons (monochrome)...")
    for density, size in NOTIFICATION_ICONS.items():
        drawable_dir = os.path.join(ANDROID_RES, f'drawable-{density}')
        os.makedirs(drawable_dir, exist_ok=True)
        
        # Create monochrome notification icon
        notification_icon = create_notification_icon(source_img, size)
        
        # Save
        notification_path = os.path.join(drawable_dir, 'ic_notification.png')
        notification_icon.save(notification_path, 'PNG')
        print(f"  ✓ {density}: ic_notification.png ({size}x{size})")
        total_icons += 1
    
    print(f"\n✨ Successfully generated {total_icons} icons!")
    print("\n📋 Summary:")
    print(f"   • Launcher icons: {len(LAUNCHER_ICONS) * 2} files")
    print(f"   • Foreground icons: {len(FOREGROUND_ICONS)} files")
    print(f"   • Notification icons: {len(NOTIFICATION_ICONS)} files")
    print(f"\n🎉 Icon generation complete!")
    
    return True


if __name__ == '__main__':
    success = generate_icons()
    exit(0 if success else 1)
