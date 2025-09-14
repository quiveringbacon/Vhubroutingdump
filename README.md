# Vhub routing dump
Dumps most vhub routes to CSV files for checking

Hello all, this is a powershell script to dump pretty much all the available vhub routing information to .csv files for troubleshooting purposes.
It'll prompt you for some info on resource group and hub name then take off and save whatever it can find to the folder given (default is "c:\temp\vwanrouting")
You'll end up with several files like this:

<img width="320" height="226" alt="example list" src="https://github.com/user-attachments/assets/3a2a435a-2bba-405f-8e63-a1d572373b17" />

Depending on what you have deployed in the vhub.
