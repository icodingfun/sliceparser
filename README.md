# sliceparser
解析ICE的协议文件,依赖lpeg和lfs模块,推荐使用LuaRocks[https://luarocks.org/]安装这两个模块。
例如
```
#ifndef  _TEST_ICE_
#define  _TEST_ICE_

module com{
	module test{
		module Protocol{
			struct Test{
				int id;
				string name;
                int age;
			};
		};
	};  
};

#endif
```
可以生成如下结果：
```
{
  Test:{
    type:struct
    name:Test
    fields:{
      1:{
        name:id
        type:int
      }
      2:{
        name:name
        type:string
      }
      3:{
        name:age
        type:int
      }
    }
  }
}
```