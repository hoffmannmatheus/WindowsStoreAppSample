using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Microsoft.VisualStudio.TestPlatform.UnitTestFramework;
using System.Threading.Tasks;

namespace Test
{
    [TestClass]
    public class MyAppTest
    {
        [TestMethod]
        public async Task TestGetGroups()
        {
            var groups = await CoverageTest.Data.SampleDataSource.GetGroupsAsync();
            Assert.IsTrue(groups.Count() > 0, "Should be true!");
        }
    }
}
