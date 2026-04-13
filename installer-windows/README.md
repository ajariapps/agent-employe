# Windows Installer Icon

The NSIS installer script references `agent.ico` as the icon for the installer.

## Icon Specifications

- **Format**: ICO (Windows Icon)
- **Sizes**: 16x16, 32x32, 48x48, 256x256 (recommended)
- **Style**: Professional, simple
- **Colors**: Blue/Green tones for monitoring/tracking theme
- **Design**: Could include elements like:
  - Eye (for monitoring)
  - Chart/graph (for analytics)
  - Computer screen (for screenshots)
  - Clock (for time tracking)

## How to Create an Icon File

### Option 1: Using Online Tools
1. Create or find a PNG image (256x256 recommended)
2. Use online converter: https://convertico.com/
3. Upload PNG and download as ICO
4. Save as `agent.ico` in this directory

### Option 2: Using GIMP (Free)
1. Open GIMP
2. Create new image 256x256
3. Design your icon
4. Export as ICO
5. Save as `agent.ico` in this directory

### Option 3: Using Adobe Illustrator/Illustrator Alternative
1. Create vector design
2. Export to PNG
3. Convert to ICO using online tool or plugin

### Option 4: Use Pre-made Icons
- Flaticon: https://www.flaticon.com/
- IconFinder: https://www.iconfinder.com/
- Icons8: https://icons8.com/

Search for terms like: "monitoring", "analytics", "tracking", "security"

## Placeholder

For now, the NSIS script will work without the icon file (it will use default NSIS icon).
To use a custom icon, place your `agent.ico` file in this directory.

## Testing Icon

After creating the icon, you can test it by building the installer:
```powershell
.\build-installer.ps1
```
