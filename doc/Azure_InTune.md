1.  Download the latest Release of the Script files from [https://github.com/nuwavepartners/connectwise\_rmm/releases](https://github.com/nuwavepartners/connectwise_rmm/releases)
2.  Extract the files. You will need the `Install-CWRMMAgent.ps1`, `NuWaveIntune.admx`, and `NuWaveIntune.adml` files in the Azure directory, and the Security Certificate from the root of the extracted files.
3.  In CW RMM, on the Devices page, select the Manage menu, Download Agent. Select the Client and main Site, take note of the Token (it will be a GUID).
4.  Login to [https://intune.microsoft.com](https://intune.microsoft.com) as a user with appropriate rights for the tenant.
    1.  Device > Managed devices > Configuration; Import ADMX tab.
        There should be an entry for NuWaveInTune.admx; if click the Import button. Select the relevant ADMX and ADML files extracted above. Next. Create. Wait until the Status shows Available.
    2.  Device > Managed devices > Configuration; Policies tab.
        There will be two separate entries:
        1.  `NuWave CW RMM Token`. If missing, Create, New Policy. Platform: Windows 10 and later. Profile type: Templates. Imported Administrative templates. Create.
            Name as it appears above. Next.
            Click the Setting Category "NuWave InTune", then "CW RMM Token". Enabled. Enter the Token acquired from RMM above. Ok. Next. Next. Add all devices. Next. Create.
        2.  `NuWave Certificate`. If missing, Create, New Policy. Platform: Windows 10 and later. Profile type: Templates, Custom. Create.
            Name as it appears above. Next.
            Add:
            1.  Name: NuWave-DevOps-Production
            2.  OMA-URI: ./Device/Vendor/MSFT/RootCATrustedCertificates/TrustedPublisher/<thumbprint>/EncodedCertificate
            3.  Data type: String
            4.  Value: <contents of cert file>
    3.  Device > Managed devices > Scripts and remediation > Remediations
        1.  NuWave CW RMM. If missing, Create.
            Name as it appears above. Next.
            Detection script file: Test-CWRMMAgent.ps1
            Remediation script file: Install-CWRMMAgent.ps1 (from the Azure folder)
            Run this script using logged-on credentials: No
            Enforce script signature check: Yes
            Run script in 64-bit PowerShell: Yes
            Next. Next. Assign to All devices. Next. Create.