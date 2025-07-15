1.  Download the latest Release of the Script files from [https://github.com/nuwavepartners/connectwise\_rmm/releases](https://github.com/nuwavepartners/connectwise_rmm/releases)
2.  Extract the files. You will need the `Install-CWRMMAgent.ps1` file in the GPO directory, and the Security Certificate from the root of the extracted files.
3.  In CW RMM, on the Devices page, select the Manage menu, Download Agent. Select the Client and main Site, take note of the Token (it will be a GUID).
4.  Login to a Domain Controller at the client.
    1.  In File Explorer find the NETLOGON folder, it it typically `C:\Windows\SysVol\Domain\Scripts`. Place the `Install-CWRMMAgent.ps1` file here.
    2.  Open Group Policy Manage Console
        1.  If a `NuWave RMM` GPO does not exist already, create one and link it to the root of the domain.
        2.  Edit the GPO.
        3.  Computer Configuration > Policies > Windows Settings > Scripts (Startup/Shutdown)
            1.  Open the Startup Properties
            2.  The Scripts tab should be empty, this is for JScript and VBScript only.
            3.  The PowerShell Scripts tab should have one entry:
                1.  The "Name" should be `\\domain.local\NETLOGON\Install-CWRMMAgent.ps1`
                    Change domain.local to be the DNS name of the client's domain.
                2.  The "Parameters" should be `-Token '12345678-1234-1234-1234-123456789012'`
                    Change the GUID to the Token acquired from RMM above.
        4.  Computer Configuration > Policies > Windows Settings > Security Settings > Public Key Policies > Trusted Publishers
            1.  There should be one entry. If not, right click, Import, select the certificate file extracted previously, Next until done.