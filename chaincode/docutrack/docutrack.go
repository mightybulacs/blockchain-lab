package main

import (
    "bytes"
    "encoding/json"
    "fmt"
    "strconv"

    "github.com/hyperledger/fabric/core/chaincode/shim"
    sc "github.com/hyperledger/fabric/protos/peer"
)


type SmartContract struct { }


type Car struct {
    Make string `json:"make"`
    Model string `json:"model"`
    Color string `json:"color"`
    Owner string `json:"owner"`
}


func (s *SmartContract) Init(APIStub shim.ChaincodeStubInterface) sc.Response {
    return shim.Success(nil)
}


func (s *SmartContract) Invoke(APIStub shim.ChaincodeStubInterface) sc.Response {
    function, args := APIStub.GetFunctionAndParameters()
    if function == "initLedger" {
        return s.initLedger(APIStub)
    } else if function == "queryCar" {
        return s.queryCar(APIStub, args)
    }
    return shim.Error("invalid SmartContract function name")
}


func (s *SmartContract) queryCar(APIStub shim.ChaincodeStubInterface, args []string) sc.Response {
    if len(args != 1) {
        return shim.Error("incorrect number of arguments: expecting 1.")
    }

    carAsBytes, _ := APIStub.GetState(args[0])
    return shim.Success(carAsBytes);
}


func (s *SmartContract) initLedger(APIStub shim.ChaincodeStubInterface) sc.Response {
    cars := []Car {
        Car{Make: "Toyota", Model: "Prius", Colour: "blue", Owner: "Tomoko"},
        Car{Make: "Ford", Model: "Mustang", Colour: "red", Owner: "Brad"},
        Car{Make: "Hyundai", Model: "Tucson", Colour: "green", Owner: "Jin Soo"},
        Car{Make: "Volkswagen", Model: "Passat", Colour: "yellow", Owner: "Max"},
        Car{Make: "Tesla", Model: "S", Colour: "black", Owner: "Adriana"},
        Car{Make: "Peugeot", Model: "205", Colour: "purple", Owner: "Michel"},
        Car{Make: "Chery", Model: "S22L", Colour: "white", Owner: "Aarav"},
        Car{Make: "Fiat", Model: "Punto", Colour: "violet", Owner: "Pari"},
        Car{Make: "Tata", Model: "Nano", Colour: "indigo", Owner: "Valeria"},
        Car{Make: "Holden", Model: "Barina", Colour: "brown", Owner: "Shotaro"}
    }

    i := 0
    for i < len(cars) {
        carAsBytes, _ := json.Marshal(cars[i])
        APIStub.PutState("CAR"+strconv.Itoa(i), carAsBytes)
        fmt.Println("added", cars[i])
        i = i + 1
    }

    return shim.Success(nil)
}


func main() {
    err := shim.Start(new(SmartContract))
    if err != nil {
        fmt.Println("[error] unable to create new SmartContract: %s", err)
    }
}