using System;
using System.IO;
using System.Runtime.InteropServices;
using WindowsInstaller;

// This utility patches a MSI installer package to use new product GUID.
// Reference msi.dll COM wrapper DLL when compiling.

namespace Qubes.BuildTools
{
    static class MsiPatch
    {
        static int Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("Usage: MsiPatch <msi path> <new GUID>");
                return 2;
            }
			
            try
            {
                string path = Path.GetFullPath(args[0]);
                string guid = args[1];
                Type t = Type.GetTypeFromProgID("WindowsInstaller.Installer");
                Installer msi = (Installer) Activator.CreateInstance(t);
                Database db = msi.OpenDatabase(path, MsiOpenDatabaseMode.msiOpenDatabaseModeTransact);
                // update summary info
                SummaryInfo summary = db.get_SummaryInformation(1);
                summary.set_Property(9, guid);
                summary.Persist();
                // update property
                string sql = string.Format("UPDATE Property SET Value='{0}' WHERE Property='ProductCode'", guid);
                View view = db.OpenView(sql);
                view.Execute(null);
                view.Close();
                sql = string.Format("UPDATE Property SET Value='{0}' WHERE Property='UpgradeCode'", guid);
                view = db.OpenView(sql);
                view.Execute(null);
                view.Close();
                db.Commit();
                Marshal.ReleaseComObject(msi);
            }
            catch (Exception e)
            {
                Console.WriteLine("Exception: {0}\n{1}", e.Message, e.StackTrace);
                return 1;
            }
            return 0;
        }
    }
}
