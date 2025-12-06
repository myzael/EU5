sensorgen can be used to generate a sensor database fragment from a monochrome image. 
Black color pixels represent a background and white pixels represent sensor points. The resolution of the mask doesn't need to match actual screen resolution since coordinates are relative and will be mapped to actual pixels after load at runtime

The sensorgen.py requires PIL to be installed on the target system. See https://pillow.readthedocs.io/en/stable/installation.html for details but in short:

python -m pip install --upgrade pip
python -m pip install --upgrade Pillow

Usage:

python sensorgen,py --input_file_path=<path to input mask> --output_file_path=<path to output file> --key_name=<name of the key in the file to generate>